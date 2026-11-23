import 'package:flutter/material.dart';

import '../utils/app_language.dart';
import '../utils/settings.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppSettings.instance,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const LText('Appearance')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(20),
            child: LText(
              'Choose how RunX Player looks. System default follows your device.',
            ),
          ),
          for (final entry in const [
            (ThemeMode.system, Icons.brightness_auto, 'System default'),
            (ThemeMode.light, Icons.light_mode, 'Light'),
            (ThemeMode.dark, Icons.dark_mode, 'Dark'),
          ])
            ListTile(
              leading: Icon(entry.$2),
              title: LText(entry.$3),
              trailing: AppSettings.instance.themeMode == entry.$1
                  ? const Icon(Icons.check_circle)
                  : const Icon(Icons.circle_outlined),
              onTap: () async {
                try {
                  await AppSettings.instance.setThemeMode(entry.$1);
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Could not save appearance. Please try again.',
                        ),
                      ),
                    );
                  }
                }
              },
            ),
        ],
      ),
    ),
  );
}
