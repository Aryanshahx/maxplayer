import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../cloud_import.dart' show ImportCancellation;
import '../playlist.dart';
import '../local_media_index.dart' show isAudioPath;
import 'dpapi.dart';

const vaultChunkBytes = 1024 * 1024;
const maxVaultFileBytes = 100 * 1024 * 1024 * 1024;
const vaultKdfIterations = 600000;
final _idPattern = RegExp(r'^[a-f0-9]{32}$');
List<int> _aad(String value) => utf8.encode('hyper-vault-v1:$value');
String _newId() {
  final random = Random.secure();
  return List.generate(
      16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

class VaultEntry {
  final String id, name;
  final int size, chunks;
  const VaultEntry(this.id, this.name, this.size, this.chunks);
}

class VaultListing {
  final List<VaultEntry> entries;
  final int unreadable;
  const VaultListing(this.entries, this.unreadable);
}

Future<List<int>> _derivePassword(
        String password, List<int> salt, int iterations) =>
    Isolate.run(() async {
      final key = await Pbkdf2(
              macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256)
          .deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
      final bytes = Uint8List.fromList(await key.extractBytes());
      key.destroy();
      return bytes;
    });

/// Versioned encrypted copies, not Android-style file hiding. Originals are never
/// moved/deleted. Only encrypted filenames/content exist in the store. AES-GCM
/// authenticates each bounded chunk and the filename/length/file-key metadata.
/// The master key is password-wrapped then protected by Windows CurrentUser DPAPI.
class EncryptedVault {
  final Directory root;
  final VaultKeyProtector protector;
  final int iterations;
  final AesGcm cipher = AesGcm.with256bits();
  SecretKey? _master;
  bool _busy = false;
  int _lockEpoch = 0;
  EncryptedVault(this.root, this.protector,
      {this.iterations = vaultKdfIterations});
  bool get unlocked => _master != null;
  File get _keyFile => File('${root.path}/account-key.bin');
  Directory get _data => Directory('${root.path}/media');
  Future<bool> exists() => _keyFile.exists();
  SecretKey get _key {
    final key = _master;
    if (key == null) throw StateError('Vault is locked.');
    return key;
  }

  Future<T> _exclusive<T>(Future<T> Function() operation) async {
    if (_busy) throw StateError('Another vault operation is active.');
    _busy = true;
    try {
      return await operation();
    } finally {
      _busy = false;
    }
  }

  Future<void> create(String password) => _exclusive(() async {
        final epoch = _lockEpoch;
        if (password.length < 12 || password.length > 128) {
          throw const FormatException('Use a password of 12–128 characters.');
        }
        if (iterations < 1 || iterations > 1000000) {
          throw StateError('Invalid KDF parameters');
        }
        await root.create(recursive: true);
        // Exclusive cross-instance setup guard. A stale guard after a crash is NOT
        // silently ignored: recovery must not replace another process's key.
        final guard = File('${root.path}/setup.lock');
        await guard.create(exclusive: true);
        SecretKey? master, derived;
        final pending = File('${_keyFile.path}.pending');
        try {
          if (await exists()) throw StateError('Vault already exists.');
          if (await _data.exists() &&
              await _data.list(followLinks: false).isEmpty == false) {
            throw StateError(
                'Existing encrypted media has no key. Restore the original account-key file; do not reset.');
          }
          master = await cipher.newSecretKey();
          final salt = cipher.newNonce();
          derived =
              SecretKey(await _derivePassword(password, salt, iterations));
          final box = await cipher.encrypt(await master.extractBytes(),
              secretKey: derived, aad: _aad('master'));
          final packet = utf8.encode(jsonEncode({
            'version': 1,
            'iterations': iterations,
            'salt': base64Encode(salt),
            'wrapped': base64Encode(box.concatenation())
          }));
          final protected = await protector.protect(packet);
          await pending.writeAsBytes(protected, flush: true);
          if (await exists()) {
            throw StateError('Vault key appeared during setup.');
          }
          await pending.rename(_keyFile.path);
          if (epoch != _lockEpoch) {
            throw StateError('Vault locked during setup.');
          }
          _master = master;
          master = null;
        } catch (_) {
          if (await pending.exists()) await pending.delete();
          rethrow;
        } finally {
          master?.destroy();
          derived?.destroy();
          await guard.delete();
        }
      });
  Future<void> unlock(String password) => _exclusive(() async {
        final epoch = _lockEpoch;
        if (password.length > 128) {
          throw const FormatException('Password too long.');
        }
        if ((await _keyFile.stat()).size > 65536) {
          throw const FormatException('Invalid key file.');
        }
        final packet = await protector.unprotect(await _keyFile.readAsBytes());
        if (packet.length > 65536) {
          throw const FormatException('Invalid key packet.');
        }
        final data = jsonDecode(utf8.decode(packet));
        if (data is! Map ||
            data['version'] != 1 ||
            data['iterations'] is! int ||
            data['salt'] is! String ||
            data['wrapped'] is! String) {
          throw const FormatException('Unsupported key format.');
        }
        final int count = data['iterations'];
        if (count < 1 || count > 1000000) {
          throw const FormatException('Invalid key work factor.');
        }
        final salt = base64Decode(data['salt']);
        if (salt.length != 12) throw const FormatException('Invalid salt.');
        final derived = SecretKey(await _derivePassword(password, salt, count));
        try {
          final bytes = await cipher.decrypt(
              SecretBox.fromConcatenation(base64Decode(data['wrapped']),
                  nonceLength: 12, macLength: 16),
              secretKey: derived,
              aad: _aad('master'));
          if (bytes.length != 32) {
            throw const FormatException('Invalid key length.');
          }
          if (epoch != _lockEpoch) {
            throw StateError('Vault locked during unlock.');
          }
          _master?.destroy();
          _master = SecretKey(bytes);
        } finally {
          derived.destroy();
        }
      });
  void lock() {
    _lockEpoch++;
    _master?.destroy();
    _master = null;
  }

  Directory _folder(String id) {
    if (!_idPattern.hasMatch(id)) {
      throw const FormatException('Invalid vault id.');
    }
    return Directory('${_data.path}/$id');
  }

  Future<Map<String, dynamic>> _metadata(String id) async {
    final file = File('${_folder(id).path}/meta.bin');
    if ((await file.stat()).size > 65536) {
      throw const FormatException('Metadata too large.');
    }
    final bytes = await cipher.decrypt(
        SecretBox.fromConcatenation(await file.readAsBytes(),
            nonceLength: 12, macLength: 16),
        secretKey: _key,
        aad: _aad('$id:meta'));
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic> ||
        value['version'] != 1 ||
        value['name'] is! String ||
        value['size'] is! int ||
        value['chunks'] is! int ||
        value['fileKey'] is! String ||
        value['chunkSize'] != vaultChunkBytes) {
      throw const FormatException('Invalid metadata.');
    }
    final int size = value['size'], chunks = value['chunks'];
    if (size < 0 ||
        size > maxVaultFileBytes ||
        chunks != (size + vaultChunkBytes - 1) ~/ vaultChunkBytes ||
        value['name'].length > 512 ||
        base64Decode(value['fileKey']).length != 32) {
      throw const FormatException('Invalid media metadata.');
    }
    return value;
  }

  Future<VaultListing> list() => _exclusive(() async {
        _key;
        final entries = <VaultEntry>[];
        var unreadable = 0;
        if (!await _data.exists()) return const VaultListing([], 0);
        await for (final entry in _data.list(followLinks: false)) {
          final id = labelFor(entry.path);
          if (entry is! Directory || !_idPattern.hasMatch(id)) continue;
          try {
            final meta = await _metadata(id);
            entries.add(
                VaultEntry(id, meta['name'], meta['size'], meta['chunks']));
          } catch (_) {
            unreadable++;
          }
        }
        entries.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return VaultListing(entries, unreadable);
      });
  Future<VaultEntry> importCopy(File source,
          {required ImportCancellation cancellation,
          required void Function(int done, int total) onProgress}) =>
      _exclusive(() async {
        _key;
        if (!isMediaPath(source.path) || isAudioPath(source.path)) {
          throw const FormatException('Choose a supported video file.');
        }
        final stat = await source.stat();
        if (stat.type != FileSystemEntityType.file ||
            stat.size > maxVaultFileBytes) {
          throw const FormatException(
              'Video unavailable or larger than 100 GB.');
        }
        final id = _newId(), name = labelFor(source.path);
        final count = (stat.size + vaultChunkBytes - 1) ~/ vaultChunkBytes;
        await _data.create(recursive: true);
        final partial = Directory('${_data.path}/.pending-$id');
        await partial.create();
        final fileKey = await cipher.newSecretKey();
        RandomAccessFile? input;
        try {
          input = await source.open();
          var done = 0;
          onProgress(0, stat.size);
          for (var i = 0; i < count; i++) {
            cancellation.check();
            final expected = min(vaultChunkBytes, stat.size - done);
            final plain = Uint8List(expected);
            var read = 0;
            while (read < expected) {
              final n = await input.readInto(plain, read, expected);
              if (n == 0) {
                throw const FileSystemException(
                    'Source changed during import.');
              }
              read += n;
            }
            final box = await cipher.encrypt(plain,
                secretKey: fileKey, aad: _aad('$id:$i:${stat.size}:$count'));
            await File('${partial.path}/$i.bin')
                .writeAsBytes(box.concatenation(), flush: true);
            plain.fillRange(0, plain.length, 0);
            done += expected;
            onProgress(done, stat.size);
          }
          cancellation.check();
          final latest = await source.stat();
          if (latest.size != stat.size || latest.modified != stat.modified) {
            throw const FileSystemException('Source changed during import.');
          }
          final meta = {
            'version': 1,
            'name': name,
            'size': stat.size,
            'chunks': count,
            'chunkSize': vaultChunkBytes,
            'fileKey': base64Encode(await fileKey.extractBytes())
          };
          final box = await cipher.encrypt(utf8.encode(jsonEncode(meta)),
              secretKey: _key, aad: _aad('$id:meta'));
          await File('${partial.path}/meta.bin')
              .writeAsBytes(box.concatenation(), flush: true);
          cancellation.check();
          await partial.rename(_folder(id).path);
          return VaultEntry(id, name, stat.size, count);
        } catch (_) {
          if (await partial.exists()) await partial.delete(recursive: true);
          rethrow;
        } finally {
          await input?.close();
          fileKey.destroy();
        }
      });

  /// Destination must not exist. Export makes a plaintext copy; never call this
  /// into a media-library/thumbnail/history cache without explicit user consent.
  Future<File> exportCopy(String id, File target,
          {required ImportCancellation cancellation,
          required void Function(int done, int total) onProgress}) =>
      _exclusive(() async {
        if (await target.exists()) {
          throw StateError(
              'Choose a new output filename. Existing files are not overwritten.');
        }
        final meta = await _metadata(id);
        final fileKey = SecretKey(base64Decode(meta['fileKey']));
        final partial = File('${target.path}.${_newId()}.partial');
        RandomAccessFile? output;
        try {
          await target.parent.create(recursive: true);
          output = await partial.open(mode: FileMode.writeOnly);
          var done = 0;
          final int size = meta['size'], count = meta['chunks'];
          onProgress(0, size);
          for (var i = 0; i < count; i++) {
            cancellation.check();
            _key;
            final chunkFile = File('${_folder(id).path}/$i.bin');
            final expected = min(vaultChunkBytes, size - done);
            if ((await chunkFile.stat()).size != expected + 28) {
              throw const FormatException(
                  'Encrypted chunk missing or invalid.');
            }
            final plain = await cipher.decrypt(
                SecretBox.fromConcatenation(await chunkFile.readAsBytes(),
                    nonceLength: 12, macLength: 16),
                secretKey: fileKey,
                aad: _aad('$id:$i:$size:$count'));
            if (plain.length != expected) {
              throw const FormatException('Invalid decoded length.');
            }
            await output.writeFrom(plain);
            if (plain is Uint8List) plain.fillRange(0, plain.length, 0);
            done += expected;
            onProgress(done, size);
          }
          cancellation.check();
          _key;
          await output.flush();
          await output.close();
          output = null;
          cancellation.check();
          _key;
          await target.create(exclusive: true);
          try {
            cancellation.check();
            _key;
            return await partial.rename(target.path);
          } catch (_) {
            if (await target.exists() && await target.length() == 0) {
              await target.delete();
            }
            rethrow;
          }
        } catch (_) {
          await output?.close();
          output = null;
          if (await partial.exists()) await partial.delete();
          rethrow;
        } finally {
          await output?.close();
          fileKey.destroy();
        }
      });
  Future<void> deleteEntry(String id) => _exclusive(() async {
        _key;
        await _metadata(id);
        await _folder(id).delete(recursive: true);
      });
}
