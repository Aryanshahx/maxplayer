#!/bin/bash
set -e

PROJECT_ROOT=~/IdeaProjects/maxplayer
cd "$PROJECT_ROOT"

echo "========================================="
echo "Max Player v75 Critical Fixes"
echo "========================================="

# 1. FIX THUMBNAIL PERSISTENCE - Move to filesDir
cat << 'EOFFILE' > android/app/src/main/kotlin/com/hypertechlabs/maxplayer/ThumbnailExtractor.kt
package com.hypertechlabs.maxplayer

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import kotlinx.coroutines.*
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest

object ThumbnailExtractor {

    private val cache = mutableMapOf<String, String>()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    fun getCachedThumbnail(context: Context, videoPath: String): String? {
        val cacheKey = videoPath.md5()
        
        if (cache.containsKey(cacheKey)) {
            val cachedPath = cache[cacheKey]!!
            if (File(cachedPath).exists()) return cachedPath
        }

        val thumbDir = File(context.filesDir, "thumbnails")
        if (!thumbDir.exists()) thumbDir.mkdirs()

        val thumbFile = File(thumbDir, "$cacheKey.jpg")
        return if (thumbFile.exists()) {
            cache[cacheKey] = thumbFile.absolutePath
            thumbFile.absolutePath
        } else null
    }

    fun extractAsync(context: Context, videoPath: String, callback: (String?) -> Unit) {
        scope.launch {
            val cached = getCachedThumbnail(context, videoPath)
            if (cached != null) {
                withContext(Dispatchers.Main) { callback(cached) }
                return@launch
            }

            val thumbnail = extractThumbnail(context, videoPath)
            withContext(Dispatchers.Main) { callback(thumbnail) }
        }
    }

    private fun extractThumbnail(context: Context, videoPath: String): String? {
        return try {
            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(videoPath)
            
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val timeUs = (duration * 1000 * 0.1).toLong()
            
            val bitmap = retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            retriever.release()

            bitmap?.let {
                val cacheKey = videoPath.md5()
                val thumbDir = File(context.filesDir, "thumbnails")
                val thumbFile = File(thumbDir, "$cacheKey.jpg")

                FileOutputStream(thumbFile).use { out ->
                    it.compress(Bitmap.CompressFormat.JPEG, 85, out)
                }
                
                cache[cacheKey] = thumbFile.absolutePath
                thumbFile.absolutePath
            }
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun String.md5(): String {
        val md = MessageDigest.getInstance("MD5")
        val digest = md.digest(toByteArray())
        return digest.joinToString("") { "%02x".format(it) }
    }

    fun preloadThumbnails(context: Context, videoPaths: List<String>) {
        scope.launch {
            videoPaths.forEach { path ->
                if (getCachedThumbnail(context, path) == null) {
                    extractThumbnail(context, path)
                }
            }
        }
    }
}
EOFFILE

# 2. UPDATE NATIVE BRIDGE - Add thumbnail methods
cat << 'EOFFILE' > android/app/src/main/kotlin/com/hypertechlabs/maxplayer/NativeBridge.kt
package com.hypertechlabs.maxplayer

import android.content.Context
import android.content.Intent
import android.speech.RecognizerIntent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class NativeBridge(private val context: Context, flutterEngine: FlutterEngine) {

    companion object {
        const val CHANNEL = "maxplayer/native"
    }

    init {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStorageRoots" -> result.success(getStorageRoots())
                "getThumbnail" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        val thumb = ThumbnailExtractor.getCachedThumbnail(context, path)
                        if (thumb != null) {
                            result.success(thumb)
                        } else {
                            ThumbnailExtractor.extractAsync(context, path) { result.success(it) }
                        }
                    } else {
                        result.success(null)
                    }
                }
                "preloadThumbnails" -> {
                    val paths = call.argument<List<String>>("paths")
                    if (paths != null) ThumbnailExtractor.preloadThumbnails(context, paths)
                    result.success(null)
                }
                "launchVoiceSearch" -> {
                    try {
                        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                            putExtra(RecognizerIntent.EXTRA_PROMPT, "Search videos...")
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        context.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getStorageRoots(): List<String> {
        val roots = mutableListOf("/storage/emulated/0")
        context.getExternalFilesDirs(null)?.forEach { file ->
            file?.absolutePath?.let { path ->
                val root = path.substring(0, path.indexOf("/Android"))
                if (!roots.contains(root)) roots.add(root)
            }
        }
        return roots
    }
}
EOFFILE

# 3. UPDATE VIDEO PROVIDER - Add thumbnail refresh on resume
cat << 'EOFFILE' > lib/providers/video_provider.dart
import 'package:flutter/foundation.dart';
import '../models/video_model.dart';
import '../services/video_scanner_service.dart';
import '../services/native_bridge.dart';

class VideoProvider with ChangeNotifier {
  List<VideoModel> _videos = [];
  bool _isLoading = false;
  bool _isInitialized = false;

  List<VideoModel> get videos => _videos;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;

  Future<void> loadVideos({bool forceReload = false}) async {
    if (_isLoading) return;
    if (_isInitialized && !forceReload) {
      await _refreshThumbnails();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      _videos = await VideoScannerService.scanAllVideos();
      _isInitialized = true;
      
      final paths = _videos.map((v) => v.path).toList();
      NativeBridge.preloadThumbnails(paths);
    } catch (e) {
      debugPrint('Error loading videos: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _refreshThumbnails() async {
    for (var video in _videos) {
      final thumbPath = await NativeBridge.getThumbnail(video.path);
      if (thumbPath != null && thumbPath != video.thumbnailPath) {
        video.thumbnailPath = thumbPath;
      }
    }
    notifyListeners();
  }

  Future<void> refreshVideos() async {
    await loadVideos(forceReload: true);
  }

  void clearVideos() {
    _videos.clear();
    _isInitialized = false;
    notifyListeners();
  }
}
EOFFILE

# 4. UPDATE NATIVE BRIDGE DART
cat << 'EOFFILE' > lib/services/native_bridge.dart
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
EOFFILE

# 5. FIX MAIN.DART - Proper SafeArea for navigation bar
cat << 'EOFFILE' > lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import 'providers/video_provider.dart';
import 'state/media_player_state.dart';
import 'state/theme_state.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VideoProvider()),
        ChangeNotifierProvider(create: (_) => MediaPlayerState()),
        ChangeNotifierProvider(create: (_) => ThemeState()),
      ],
      child: Consumer<ThemeState>(
        builder: (context, themeState, _) {
          return MaterialApp(
            title: 'Max Player',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.blue,
                brightness: Brightness.dark,
              ),
            ),
            builder: (context, child) {
              return SafeArea(
                top: false,
                bottom: true,
                left: false,
                right: false,
                child: child!,
              );
            },
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
EOFFILE

# 6. UPDATE HOME SCREEN - Add app resume listener
cat << 'EOFFILE' > lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/video_provider.dart';
import '../widgets/video_grid.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VideoProvider>().loadVideos();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<VideoProvider>().loadVideos();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Max Player'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<VideoProvider>().refreshVideos(),
          ),
        ],
      ),
      body: Consumer<VideoProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && !provider.isInitialized) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.videos.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.video_library_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No videos found'),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => provider.refreshVideos(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Scan Again'),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => provider.refreshVideos(),
            child: VideoGrid(videos: provider.videos),
          );
        },
      ),
    );
  }
}
EOFFILE

# 7. CREATE ROUNDED LAUNCHER ICONS
mkdir -p android/app/src/main/res/drawable
mkdir -p android/app/src/main/res/mipmap-anydpi-v26

cat << 'EOFFILE' > android/app/src/main/res/drawable/ic_launcher_background.xml
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path android:fillColor="#2196F3" android:pathData="M0,0h108v108h-108z"/>
</vector>
EOFFILE

cat << 'EOFFILE' > android/app/src/main/res/drawable/ic_launcher_foreground.xml
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <group android:scaleX="0.5" android:scaleY="0.5" android:translateX="27" android:translateY="27">
        <path android:fillColor="#FFFFFF" android:pathData="M40,20L40,88L80,54Z"/>
    </group>
</vector>
EOFFILE

cat << 'EOFFILE' > android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>
EOFFILE

cat << 'EOFFILE' > android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>
EOFFILE

# 8. UPDATE VERSION IN PUBSPEC
sed -i 's/version: .*/version: 1.0.0+75/' pubspec.yaml

# 9. UPDATE VERSION IN BUILD.GRADLE.KTS
sed -i 's/versionCode = .*/versionCode = 75/' android/app/build.gradle.kts
sed -i 's/versionName = ".*"/versionName = "1.0.0"/' android/app/build.gradle.kts

echo ""
echo "✅ v75 updates complete!"
echo "   - Thumbnails now persist in filesDir"
echo "   - Auto-reload on app resume"
echo "   - Navigation bar fixed with SafeArea"
echo "   - Rounded launcher icon"
