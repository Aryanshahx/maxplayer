import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_player/vault/encrypted_vault.dart';
import 'package:hyper_player/vault/dpapi.dart';
import 'package:hyper_player/cloud_import.dart';

/// Test-only adapter. Production always uses WindowsDpapiProtector and never
/// silently falls back to this. Crypto behaviour tested separately from DPAPI.
class TestProtector implements VaultKeyProtector {
  int writes = 0, reads = 0;
  @override
  Future<List<int>> protect(List<int> value) async {
    writes++;
    return [...value];
  }

  @override
  Future<List<int>> unprotect(List<int> value) async {
    reads++;
    return [...value];
  }
}

void main() {
  late Directory root;
  late EncryptedVault vault;
  late TestProtector protector;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('hyper-vault-');
    protector = TestProtector();
    vault = EncryptedVault(Directory('${root.path}/vault'), protector,
        iterations: 100);
  });
  tearDown(() async {
    vault.lock();
    await root.delete(recursive: true);
  });
  test('Setup requires a strong password and invokes account-key protection',
      () async {
    await expectLater(vault.create('1234'), throwsFormatException);
    await vault.create('a test password 123');
    expect(protector.writes, 1);
    expect(vault.unlocked, isTrue);
    vault.lock();
    expect(vault.unlocked, isFalse);
    await expectLater(vault.list(), throwsStateError);
  });
  test('Wrong password fails authentication without erasing the vault',
      () async {
    await vault.create('a test password 123');
    vault.lock();
    await expectLater(vault.unlock('not the right password'),
        throwsA(isA<SecretBoxAuthenticationError>()));
    expect(vault.unlocked, isFalse);
    expect(await vault.exists(), isTrue);
    await vault.unlock('a test password 123');
    expect(vault.unlocked, isTrue);
  });
  test('Multi-chunk import/export is byte exact and original is untouched',
      () async {
    await vault.create('a test password 123');
    final source = File('${root.path}/Private Movie.mp4');
    final bytes = Uint8List.fromList(
        List.generate(vaultChunkBytes + 123, (i) => i % 251));
    await source.writeAsBytes(bytes);
    final entry = await vault.importCopy(source,
        cancellation: ImportCancellation(), onProgress: (_, total) {});
    expect(entry.chunks, 2);
    expect(await source.readAsBytes(), bytes);
    final listing = await vault.list();
    expect(listing.entries.single.name, 'Private Movie.mp4');
    final output = await vault.exportCopy(
        entry.id, File('${root.path}/export/out.mp4'),
        cancellation: ImportCancellation(), onProgress: (_, total) {});
    expect(await output.readAsBytes(), bytes);
    final metadata = await File('${root.path}/vault/media/${entry.id}/meta.bin')
        .readAsBytes();
    expect(String.fromCharCodes(metadata), isNot(contains('Private Movie')));
  });
  test('Tampered ciphertext cannot export a completed plaintext file',
      () async {
    await vault.create('a test password 123');
    final source = File('${root.path}/movie.mp4');
    await source.writeAsString('SECRET VIDEO CONTENT THAT MUST AUTHENTICATE');
    final entry = await vault.importCopy(source,
        cancellation: ImportCancellation(), onProgress: (_, total) {});
    final chunk = File('${root.path}/vault/media/${entry.id}/0.bin');
    final bytes = await chunk.readAsBytes();
    bytes[15] ^= 1;
    await chunk.writeAsBytes(bytes);
    final output = File('${root.path}/export/out.mp4');
    await expectLater(
        vault.exportCopy(entry.id, output,
            cancellation: ImportCancellation(), onProgress: (_, total) {}),
        throwsA(isA<SecretBoxAuthenticationError>()));
    expect(await output.exists(), isFalse);
    expect(await output.parent.list().toList(), isEmpty);
  });
  test('Cancelled encryption removes pending chunks and keeps original',
      () async {
    await vault.create('a test password 123');
    final source = File('${root.path}/movie.mp4');
    await source.writeAsBytes(Uint8List(vaultChunkBytes + 1));
    final token = ImportCancellation();
    await expectLater(
        vault.importCopy(source, cancellation: token,
            onProgress: (done, total) {
          if (done > 0) token.cancel();
        }),
        throwsA(isA<ImportCancelled>()));
    expect((await vault.list()).entries, isEmpty);
    expect(
        await Directory('${root.path}/vault/media').list().toList(), isEmpty);
    expect(await source.exists(), isTrue);
  });
  test('Missing/tampered metadata is counted, never silently deleted',
      () async {
    await vault.create('a test password 123');
    final source = File('${root.path}/movie.mp4');
    await source.writeAsString('data');
    final entry = await vault.importCopy(source,
        cancellation: ImportCancellation(), onProgress: (_, total) {});
    await File('${root.path}/vault/media/${entry.id}/meta.bin')
        .writeAsBytes([1, 2, 3]);
    final listing = await vault.list();
    expect(listing.unreadable, 1);
    expect(listing.entries, isEmpty);
    expect(await Directory('${root.path}/vault/media/${entry.id}').exists(),
        isTrue);
  });
  test('Export never overwrites an existing destination', () async {
    await vault.create('a test password 123');
    final source = File('${root.path}/movie.mp4');
    await source.writeAsString('source');
    final entry = await vault.importCopy(source,
        cancellation: ImportCancellation(), onProgress: (_, total) {});
    final output = File('${root.path}/out.mp4');
    await output.writeAsString('KEEP EXISTING');
    await expectLater(
        vault.exportCopy(entry.id, output,
            cancellation: ImportCancellation(), onProgress: (_, total) {}),
        throwsStateError);
    expect(await output.readAsString(), 'KEEP EXISTING');
  });
  test('Losing key file does not permit creating a new key over old ciphertext',
      () async {
    await vault.create('a test password 123');
    final source = File('${root.path}/movie.mp4');
    await source.writeAsString('private');
    await vault.importCopy(source,
        cancellation: ImportCancellation(), onProgress: (_, total) {});
    vault.lock();
    await File('${root.path}/vault/account-key.bin').delete();
    await expectLater(vault.create('another long password'), throwsStateError);
  });
  test('Traversal identifiers and locked deletion are rejected', () async {
    await vault.create('a test password 123');
    await expectLater(vault.deleteEntry('../escape'), throwsFormatException);
    vault.lock();
    await expectLater(vault.deleteEntry('0' * 32), throwsStateError);
  });
  test('Concurrent setup cannot replace another instance key', () async {
    final other = EncryptedVault(Directory('${root.path}/vault'), protector,
        iterations: 100);
    addTearDown(other.lock);
    var success = 0;
    Future<void> attempt(EncryptedVault store) async {
      try {
        await store.create('a test password 123');
        success++;
      } catch (_) {}
    }

    await Future.wait([attempt(vault), attempt(other)]);
    expect(success, 1);
    vault.lock();
    other.lock();
    await vault.unlock('a test password 123');
    expect(vault.unlocked, isTrue);
  });
  test('Lock during key setup cannot reopen vault after async completion',
      () async {
    final setup = vault.create('a test password 123');
    vault.lock();
    await expectLater(setup, throwsStateError);
    expect(vault.unlocked, isFalse);
    expect(await vault.exists(), isTrue);
    await vault.unlock('a test password 123');
    expect(vault.unlocked, isTrue);
  });
  test('Production DPAPI fails closed outside Windows', () async {
    if (!Platform.isWindows) {
      await expectLater(
          WindowsDpapiProtector().protect([1, 2, 3]), throwsUnsupportedError);
    }
  });
}
