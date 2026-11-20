import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef _DriveMask = Uint32 Function();
typedef _DriveType = Uint32 Function(Pointer<Utf16> root);

List<String> fixedDriveRootsFromMask(
        int mask, int Function(String root) typeOf) =>
    [
      for (var drive = 0; drive < 26; drive++)
        if (mask & (1 << drive) != 0)
          if (typeOf('${String.fromCharCode(65 + drive)}:\\') == 3)
            '${String.fromCharCode(65 + drive)}:\\'
    ];

/// Enumerates drive names only. Does not enumerate media, request credentials,
/// scan network shares or elevate permissions. Scanning requires separate consent.
List<String> windowsFixedDriveRoots() {
  if (!Platform.isWindows) {
    throw UnsupportedError('Windows local drives required.');
  }
  final api = DynamicLibrary.open('kernel32.dll');
  final mask =
      api.lookupFunction<_DriveMask, int Function()>('GetLogicalDrives')();
  final type = api.lookupFunction<_DriveType, int Function(Pointer<Utf16>)>(
      'GetDriveTypeW');
  return fixedDriveRootsFromMask(mask, (root) {
    final name = root.toNativeUtf16();
    try {
      return type(name);
    } finally {
      malloc.free(name);
    }
  });
}
