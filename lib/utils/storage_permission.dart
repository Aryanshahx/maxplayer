import 'package:permission_handler/permission_handler.dart';

import '../services/native_bridge.dart';

/// v40: THE one place that asks for storage read access. Two other spots
/// (the Private folder's "+" flow and the library's long-press "hide" flow)
/// asked ONLY for "All files access", which resolves denied FOREVER on
/// Android 10 and older (vivo 1908, API 27) - those phones kept "asking
/// storage permission even though it is enabled", exactly like the library
/// scanner did before v38.
///
/// Android 11+ (API 30+): request "All files access".
/// Android 10 and older: that concept does not exist - the classic Storage
/// runtime permission is the correct ask there.
///
/// Returns true when reading storage is allowed (calling request() when
/// already granted resolves granted without showing any dialog).
Future<bool> ensureStorageAccess() async {
  PermissionStatus status;
  try {
    status = await Permission.manageExternalStorage.request();
  } catch (_) {
    // Some skins/Go builds lack the "All files access" screen entirely and
    // the request can throw instead of returning denied.
    status = PermissionStatus.denied;
  }
  if (!status.isGranted && (await NativeBridge.sdkInt()) < 30) {
    status = await Permission.storage.request();
  }
  if ((await NativeBridge.sdkInt()) >= 33) {
    // v106-fix: Android 13+ lists Photos / Videos / Music separately in App
    // info and gates MediaStore reads on them - ask even when All-files is
    // granted, so nothing shows "Not allowed".
    final videos = await Permission.videos.request();
    await Permission.photos.request();
    await Permission.audio.request();
    // All-files denied but videos granted: MediaStore still serves videos.
    if (!status.isGranted && videos.isGranted) return true;
  }
  return status.isGranted;
}
