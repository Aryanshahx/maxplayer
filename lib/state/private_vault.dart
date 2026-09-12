import 'dart:io';

import '../services/native_bridge.dart';
import '../utils/local_store.dart';
import '../utils/sha256.dart';

/// Private folder ("vault") — old-app behaviour, same-to-same.
///
/// Mechanism (MX Player / PlayIt style): the video FILE IS MOVED into the
/// app's own directory. Android blocks Gallery / Photos / Files from looking
/// inside another app's private directory, so a hidden video disappears from
/// the rest of the phone, and Max Player lists it only after the PIN.
///
/// The PIN protects the list; the file location is the real hiding. Only the
/// PIN hash (never the PIN itself) is stored, in the app's local settings.
///
/// ⚠ Uninstalling the app deletes the app's private directory — hidden
/// videos along with it. The UI always offers "Move out of Private" first.
class PrivateVault {
  /// Legacy hardcoded location (kept only as a fallback for hosts where the
  /// native side can't provide the framework directory).
  static const String vaultDirPath =
      '/storage/emulated/0/Android/data/com.maxplayer.maxplayer/files/Private';

  /// Videos moved OUT of the vault land here.
  static const String unhideDirPath = '/storage/emulated/0/Movies';

  static const Set<String> videoExts = {
    '.mp4', '.mkv', '.webm', '.avi', '.mov', '.wmv', '.flv', '.ts', '.m2ts',
    '.mpg', '.mpeg', '.3gp', '.vob', '.m4v',
  };

  /// In-process change counter: hide()/unhide() bump it. The library screen
  /// compares it when the Private folder closes and rescans ONLY when
  /// something actually moved.
  static int revision = 0;

  /// True when [path] already lives inside the vault.
  static bool isPrivatePath(String path) =>
      path.startsWith(vaultDirPath) || path.contains('/files/Private/');

  final LocalStore _store = LocalStore();

  String _hashPin(String pin) => sha256Hex('maxplayer.vault::$pin');

  Future<bool> hasPin() async => (await _store.vaultPinHash()).isNotEmpty;

  Future<bool> verifyPin(String pin) async {
    final stored = await _store.vaultPinHash();
    return stored.isNotEmpty && stored == _hashPin(pin);
  }

  Future<void> setPin(String pin) => _store.setVaultPinHash(_hashPin(pin));

  /// "Forgot PIN": deletes the stored hash. The VIDEOS ARE SAFE — the PIN
  /// only guards the door, the hiding is the folder itself; after a reset
  /// the user simply creates a fresh PIN and the same videos appear.
  Future<void> resetPin() => _store.setVaultPinHash('');

  Directory? _dirCache;

  /// The vault directory, resolved (and created) THROUGH THE FRAMEWORK —
  /// Android's getExternalFilesDir creates it with the right ownership and
  /// needs NO storage permission at all.
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
      return _dirCache = d;
    }

    // Native gave nothing (very old build / tests) — legacy hardcoded path.
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

  /// Video files currently inside the vault (name-sorted).
  Future<List<File>> listVideos() async {
    final d = await _dir();
    final files = d
        .listSync()
        .whereType<File>()
        .where((f) {
          final name = f.path.toLowerCase();
          final dot = name.lastIndexOf('.');
          final ext = dot >= 0 ? name.substring(dot) : '';
          return videoExts.contains(ext);
        })
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  /// Moves [srcPath] into the vault and returns the new file. API <= 28
  /// renames instantly; on scoped storage (API 29+) we READ the video with
  /// the media permission but deleting the original needs the system's
  /// consent dialog, which shows once the copy is safely inside.
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
    revision++; // vault contents changed
    // Refresh the gallery scan for the OLD location so it disappears.
    // Best-effort only - a failed rescan must NOT undo a good move.
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
      // Scoped storage: export through MediaStore into the public Movies
      // folder (auto-indexed - no rescan needed), then drop the vault copy.
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
    revision++;
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
      // If the delete fails we roll the copy back — no silent duplicate.
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
