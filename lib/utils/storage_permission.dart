import 'package:permission_handler/permission_handler.dart';

import '../services/native_bridge.dart';

/// Version-correct storage-read ask, same as the old app:
///
/// Android 13+ (API 33+): videos / photos / audio are separate runtime
/// grants that gate MediaStore reads.
/// Android 10-12 (API 29-32): READ_EXTERNAL_STORAGE grants media reads.
/// Android 9 and older: the classic Storage permission.
///
/// Returns true when reading videos is allowed (calling request() when
/// already granted resolves granted without showing any dialog). The
/// Private folder's "+" flow and the library long-press "hide" flow route
/// through here too - keep it that way.
Future<bool> ensureStorageAccess() async {
  final sdk = await NativeBridge.sdkInt();
  PermissionStatus status;
  try {
    if (sdk >= 33) {
      status = await Permission.videos.request();
      await Permission.photos.request();
      await Permission.audio.request();
    } else {
      status = await Permission.storage.request();
    }
  } catch (_) {
    // Some skins/Go builds lack a permission screen entirely and the
    // request can throw instead of returning denied.
    status = PermissionStatus.denied;
  }
  return status.isGranted;
}
