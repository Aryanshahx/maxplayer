import 'package:flutter/services.dart';

class NativeBridge {
  static const _channel = MethodChannel('maxplayer/native');

  static Future<List<String>> storageRoots() async {
    try {
      final List<dynamic> roots = await _channel.invokeMethod('getStorageRoots');
      return roots.cast<String>();
    } catch (e) {
      return ['/storage/emulated/0'];
    }
  }

  static Future<String?> getThumbnail(String videoPath) async {
    try {
      return await _channel.invokeMethod('getThumbnail', {'path': videoPath});
    } catch (e) {
      return null;
    }
  }

  static Future<void> preloadThumbnails(List<String> videoPaths) async {
    try {
      await _channel.invokeMethod('preloadThumbnails', {'paths': videoPaths});
    } catch (e) {}
  }

  static Future<void> launchSystemVoiceSearch() async {
    try {
      await _channel.invokeMethod('launchVoiceSearch');
    } catch (e) {
      throw Exception('Voice search not available');
    }
  }
}
