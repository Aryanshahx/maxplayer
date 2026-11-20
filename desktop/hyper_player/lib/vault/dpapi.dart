import 'dart:async';
import 'dart:convert';
import 'dart:io';

abstract interface class VaultKeyProtector {
  Future<List<int>> protect(List<int> bytes);
  Future<List<int>> unprotect(List<int> bytes);
}

/// Windows CurrentUser DPAPI. Sensitive payload travels through stdin, never
/// command-line arguments, environment variables, logging or SharedPreferences.
/// This fails closed on non-Windows or blocked PowerShell; no insecure fallback.
class WindowsDpapiProtector implements VaultKeyProtector {
  @override
  Future<List<int>> protect(List<int> bytes) => _run(bytes, true);
  @override
  Future<List<int>> unprotect(List<int> bytes) => _run(bytes, false);
  Future<List<int>> _run(List<int> bytes, bool encrypt) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows user-account protection is required.');
    }
    final script =
        r'''$ErrorActionPreference='Stop';Add-Type -AssemblyName System.Security;$data=[Convert]::FromBase64String([Console]::In.ReadToEnd());$result=[System.Security.Cryptography.ProtectedData]::METHOD($data,$null,[System.Security.Cryptography.DataProtectionScope]::CurrentUser);[Console]::Out.Write([Convert]::ToBase64String($result))'''
            .replaceFirst('METHOD', encrypt ? 'Protect' : 'Unprotect');
    final encoded = base64Encode(
        script.codeUnits.expand((c) => [c & 255, c >> 8]).toList());
    final systemRoot = Platform.environment['SystemRoot'];
    if (systemRoot == null ||
        !RegExp(r'^[A-Za-z]:[\\/]').hasMatch(systemRoot)) {
      throw StateError('Windows system directory is unavailable.');
    }
    final executable =
        '$systemRoot\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
    final process = await Process.start(executable, [
      '-NoLogo',
      '-NoProfile',
      '-NonInteractive',
      '-EncodedCommand',
      encoded
    ]);
    Future<List<int>> bounded(Stream<List<int>> stream) async {
      final result = <int>[];
      await for (final part in stream) {
        if (result.length + part.length > 131072) {
          process.kill();
          throw StateError('Windows account-key response exceeded its limit.');
        }
        result.addAll(part);
      }
      return result;
    }

    final output = bounded(process.stdout);
    final errors = bounded(process.stderr);
    try {
      return await (() async {
        // Attach listeners to both pipes before writing input; drain concurrently.
        final replies = Future.wait([output, errors]);
        process.stdin.write(base64Encode(bytes));
        await process.stdin.close();
        final parts = await replies;
        final code = await process.exitCode;
        if (code != 0) {
          throw StateError('Windows account-key protection failed.');
        }
        return base64Decode(utf8.decode(parts.first).trim());
      })()
          .timeout(const Duration(seconds: 20));
    } finally {
      process.kill();
    }
  }
}
