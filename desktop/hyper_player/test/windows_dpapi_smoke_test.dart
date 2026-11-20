import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_player/vault/dpapi.dart';

void main() {
  test(
      'Windows DPAPI protects and restores a nonsecret fixture for this account',
      () async {
    final adapter = WindowsDpapiProtector();
    final plain = List<int>.generate(32, (i) => i);
    final wrapped = await adapter.protect(plain);
    expect(wrapped, isNot(equals(plain)));
    expect(await adapter.unprotect(wrapped), plain);
    await expectLater(adapter.unprotect([1, 2, 3]), throwsA(anything));
  }, skip: !Platform.isWindows, timeout: const Timeout(Duration(minutes: 2)));
}
