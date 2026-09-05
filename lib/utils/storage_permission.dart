import 'package:permission_handler/permission_handler.dart';

import '../services/native_bridge.dart';

/// v112 (Play policy): all-files access (MANAGE_EXTERNAL_STORAGE) is GONE -
/// Google rejected it as non-core, and scoped storage covers the app's real
/// needs. This one helper still asks for media-read access with the
/// version-correct permission set:
///
/// Android 13+ (API 33+): videos/photos/audio are separate runtime grants
/// that gate MediaStore reads.
/// Android 10-12 (API 29-32): READ_EXTERNAL_STORAGE grants media reads.
/// Android 9 and older: the classic Storage permission.
///
/// Returns true when reading videos is allowed (calling request() when
/// already granted resolves granted without showing any dialog). v40 note:
/// the Private folder's "+" flow and the library's long-press "hide" flow
/// route through here too - keep it that way.
Future<bool> ensureStorageAccess() async {
  final sdk = await NativeBridge.sdkInt();
  PermissionStatus status;
  try {
    if (sdk >= 33) {
      status = await Permission.videos.request();
      // v106-fix: Android 13+ lists Photos / Music separately in App info -
      // ask alongside so nothing reads as "Not allowed". The video grant is
      // what this helper reports; either subset granted is fine.
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
