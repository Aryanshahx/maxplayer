import 'dart:io';

import '../services/native_bridge.dart';
import '../utils/sha256.dart';

/// Private folder ("vault"), v21.
///
/// Mechanism (same idea as MX Player / PlayIt): the video FILE IS MOVED into
/// the app's own directory. Android blocks Gallery / Photos / Files from
/// looking inside another app's private directory, so a hidden video
/// disappears from the rest of the phone, and Max Player lists it only
/// after the PIN.
///
/// The PIN protects the list; the file location is the real hiding. The PIN
/// hash (never the PIN itself) is stored in the app's settings store.
///
/// ⚠ Uninstalling the app deletes the app's private directory - hidden
/// videos along with it. The UI always offers "Move out of Private" first.
class PrivateVault {
  static const String _pinKey = 'vault.pinHash';

  /// v26: in-process change counter - hide()/unhide() bump it. The library
  /// screen compares it when the Private folder closes and rescans ONLY
  /// when something actually moved (a plain visit no longer reloads the
  /// whole library - "refreshing every time when we return").
  static int revision = 0;

  /// v21-v23 vault location (hardcoded). v24 keeps it ONLY as a legacy
  /// source: the vault now lives in the directory the Android framework
  /// hands the app via getExternalFilesDir - on most phones that is the
  /// exact same folder, on devices where mkdir-ing it by hand is denied
  /// (errno 13 crash) the framework one always works.
  static const String vaultDirPath =
      '/storage/emulated/0/Android/data/com.hypertechlabs.maxplayer/files/Private';

  /// Videos moved OUT of the vault land here.
  static const String unhideDirPath = '/storage/emulated/0/Movies';

  static const Set<String> videoExts = {
    '.mp4', '.mkv', '.webm', '.avi', '.mov', '.wmv', '.flv', '.ts', '.m2ts',
    '.mpg', '.mpeg', '.3gp', '.vob', '.m4v',
  };

  /// True when [path] already lives inside the vault (either the legacy
  /// hardcoded location or any framework-provided one - both end in the
  /// "/files/Private/" tail of the app's private directory).
  static bool isPrivatePath(String path) =>
      path.startsWith(vaultDirPath) || path.contains('/files/Private/');

  String _hashPin(String pin) => sha256Hex('maxplayer.vault::$pin');

  Future<bool> hasPin() async {
    final s = await NativeBridge.loadSettings();
    return (s[_pinKey] ?? '').isNotEmpty;
  }

  Future<bool> verifyPin(String pin) async {
    final s = await NativeBridge.loadSettings();
    final stored = s[_pinKey] ?? '';
    return stored.isNotEmpty && stored == _hashPin(pin);
  }

  Future<void> setPin(String pin) =>
      NativeBridge.saveSetting(_pinKey, _hashPin(pin));

  /// v25 "Forgot PIN": deletes the stored hash. The VIDEOS ARE SAFE - the
  /// PIN only guards the door, the hiding is the folder itself; after a
  /// reset the user simply creates a fresh PIN and the same videos appear.
  /// (Some other players wipe everything on a forgotten PIN - we don't.)
  Future<void> resetPin() => NativeBridge.saveSetting(_pinKey, '');

  Directory? _dirCache;

  /// The vault directory, resolved (and created) THROUGH THE FRAMEWORK.
  /// v24: the old code did `Directory(hardcoded).create()` from Dart,
  /// which some devices refuse with PathAccessException errno=13 when the
  /// package folder inside Android/data is missing - the PIN screen could
  /// crash the whole app (unhandled zone error). Native's
  /// getExternalFilesDir creates it with the right ownership and needs NO
  /// storage permission at all; then any v21-v23 leftovers are migrated in.
  Future<Directory> _dir() async {
    final cached = _dirCache;
    if (cached != null) return cached;

    final fromNative = await NativeBridge.vaultDirPath();
    if (fromNative != null) {
      final d = Directory(fromNative);
      if (!d.existsSync()) {
        try {
          await d.create(recursive: true);
        } catch (_) {
          throw FileSystemException(
            'Vault storage is not available on this device',
            fromNative,
          );
        }
      }
      if (fromNative != vaultDirPath) await _migrateLegacyTo(d);
      return _dirCache = d;
    }

    // Native gave nothing (very old build) - legacy hardcoded path.
    final d = Directory(vaultDirPath);
    if (!d.existsSync()) {
      try {
        await d.create(recursive: true);
      } catch (_) {
        throw const FileSystemException(
          'Vault storage is not available - allow storage permission for '
          'Max Player and try again',
        );
      }
    }
    return _dirCache = d;
  }

  /// Moves videos hidden by v21-v23 builds (legacy hardcoded path) into the
  /// current vault directory. Best-effort: anything unreadable is left in
  /// place rather than breaking the vault.
  Future<void> _migrateLegacyTo(Directory target) async {
    try {
      final legacy = Directory(vaultDirPath);
      if (!legacy.existsSync()) return;
      await for (final e in legacy.list(followLinks: false)) {
        if (e is! File) continue;
        try {
          final dest = await _uniqueIn(target, e.path);
          await _move(e, dest);
        } catch (_) {
          // Leave this file; try the next one.
        }
      }
    } catch (_) {}
  }

  /// Video files currently inside the vault (name-sorted).
  Future<List<File>> listVideos() async {
    final d = await _dir();
    final files = d
        .listSync()
        .whereType<File>()
        .where((f) =>
            videoExts.contains(f.path.toLowerCase().split('.').last.isEmpty
                ? ''
                : '.${f.path.toLowerCase().split('.').last}'))
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  /// Moves [srcPath] into the vault and returns the new file. API <= 28
  /// renames instantly; on scoped storage (API 29+) we may READ the video
  /// with the media permission but deleting the original needs the system's
  /// consent dialog (v112), which shows once the copy is safely inside.
  Future<File> hide(String srcPath) async {
    final src = File(srcPath);
    if (!src.existsSync()) {
      throw const FileSystemException('Video file not found');
    }
    final target = await _uniqueIn(await _dir(), srcPath);
    final File moved;
    if ((await NativeBridge.sdkInt()) >= 29) {
      moved = await src.copy(target);
      final deleted = await NativeBridge.requestMediaDelete([srcPath]);
      if (!deleted) {
        // Roll back so a declined delete never leaves a silent duplicate.
        try {
          await moved.delete();
        } catch (_) {}
        throw const FileSystemException('Delete of the original was declined');
      }
    } else {
      moved = await _move(src, target);
    }
    revision++; // v26: vault contents changed
    // Refresh the gallery scan for the OLD location so it disappears.
    // v22: best-effort only - a failed rescan must NOT undo a good move.
    try {
      await NativeBridge.scanFile(srcPath);
    } catch (_) {}
    return moved;
  }

  /// Moves a vault file back to public storage (/storage/emulated/0/Movies).
  Future<File> unhide(String hiddenPath) async {
    final src = File(hiddenPath);
    if (!src.existsSync()) {
      throw const FileSystemException('Hidden video not found');
    }
    if ((await NativeBridge.sdkInt()) >= 29) {
      // v112 / scoped storage: export through MediaStore into the public
      // Movies folder (auto-indexed - no rescan needed), then drop the
      // vault copy, which lives in our own app directory.
      final name = hiddenPath.split('/').last;
      final saved = await NativeBridge.savePickedVideoToDevice(
        cachePath: hiddenPath,
        name: name,
        relativePath: 'Movies',
      );
      if (saved == null) {
        throw const FileSystemException('Could not export the video');
      }
      await src.delete();
      revision++;
      final outPath = saved['path']?.toString();
      return File(
        outPath != null && outPath.isNotEmpty ? outPath : '$unhideDirPath/$name',
      );
    }
    final destDir = Directory(unhideDirPath);
    if (!destDir.existsSync()) await destDir.create(recursive: true);
    final target = await _uniqueIn(destDir, hiddenPath);
    final moved = await _move(src, target);
    revision++; // v26: vault contents changed
    try {
      await NativeBridge.scanFile(moved.path); // visible to gallery again
    } catch (_) {}
    return moved;
  }

  Future<String> _uniqueIn(Directory dir, String fromPath) async {
    var name = fromPath.split('/').last;
    var dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var candidate = '${dir.path}/$name';
    var i = 2;
    while (File(candidate).existsSync()) {
      candidate = '${dir.path}/$stem ($i)$ext';
      i++;
    }
    return candidate;
  }

  Future<File> _move(File src, String targetPath) async {
    try {
      return await src.rename(targetPath);
    } on FileSystemException {
      // Cross-volume move (e.g. SD card): copy, then remove the original.
      // v22: if the delete fails we roll the copy back - the old code
      // left a silent duplicate in the vault AND reported failure, which
      // made "Private folder not working" reports un-debuggable.
      final copied = await src.copy(targetPath);
      try {
        await src.delete();
      } catch (_) {
        try {
          await copied.delete();
        } catch (_) {}
        throw const FileSystemException(
          'Could not remove the original file - allow storage permission '
          'for Max Player and try again',
        );
      }
      return copied;
    }
  }
}
