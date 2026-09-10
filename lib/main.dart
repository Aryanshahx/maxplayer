import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/library_screen.dart';
import 'theme.dart';
import 'utils/crash_log.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized(); // MPV core
  await CrashLog.init(); // forensics armed before first frame
  CrashLog.crumb('app.start');
  runApp(const MaxPlayerApp());
}

class MaxPlayerApp extends StatelessWidget {
  const MaxPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MaxPlayer',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const LibraryScreen(),
    );
  }
}
