import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'state/media_player_state.dart';
import 'state/video_library_state.dart';
import 'screens/library_screen.dart';

void main() {
  // Must be called before any media_kit Player is created.
  MediaKit.ensureInitialized();
  runApp(const MaxPlayerApp());
}

class MaxPlayerApp extends StatefulWidget {
  const MaxPlayerApp({super.key});

  @override
  State<MaxPlayerApp> createState() => _MaxPlayerAppState();
}

class _MaxPlayerAppState extends State<MaxPlayerApp> {
  final library = VideoLibraryState();
  final player = MediaPlayerState();

  @override
  void dispose() {
    player.dispose();
    library.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Max Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0a0a0f),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFA855F7),
          brightness: Brightness.dark,
        ),
      ),
      home: LibraryScreen(library: library, player: player),
    );
  }
}
