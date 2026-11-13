import 'package:flutter/material.dart';
import '../utils/app_language.dart';

const languageEnglishNames = <String, String>{
  'en': 'English',
  'hi': 'Hindi',
  'bn': 'Bengali',
  'te': 'Telugu',
  'mr': 'Marathi',
  'ta': 'Tamil',
  'ur': 'Urdu',
  'gu': 'Gujarati',
  'kn': 'Kannada',
  'ml': 'Malayalam',
  'pa': 'Punjabi',
  'or': 'Odia',
  'as': 'Assamese',
  'ne': 'Nepali',
  'si': 'Sinhala',
  'ar': 'Arabic',
  'fa': 'Persian',
  'he': 'Hebrew',
  'tr': 'Turkish',
  'ru': 'Russian',
  'uk': 'Ukrainian',
  'de': 'German',
  'fr': 'French',
  'es': 'Spanish',
  'pt': 'Portuguese',
  'it': 'Italian',
  'nl': 'Dutch',
  'pl': 'Polish',
  'ro': 'Romanian',
  'el': 'Greek',
  'id': 'Indonesian',
  'ms': 'Malay',
  'vi': 'Vietnamese',
  'th': 'Thai',
  'ko': 'Korean',
  'ja': 'Japanese',
  'zh': 'Chinese (Simplified)',
  'sw': 'Swahili',
  'cs': 'Czech',
  'hu': 'Hungarian',
};

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});
  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  String _search = '';
  bool _busy = false;
  Future<void> _choose(String code) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await AppLanguage.instance.setLanguage(code);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LText('Could not save language. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LText('Language')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: const LInputDecoration(
              hintText: 'Search languages',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: ListView(
            children: [
              ListTile(
                title: const LText('System default'),
                leading: const Icon(Icons.phone_android),
                trailing: AppLanguage.instance.code == 'system'
                    ? const Icon(Icons.check)
                    : null,
                onTap: _busy ? null : () => _choose('system'),
              ),
              for (final l in uiLanguages)
                if (_search.isEmpty ||
                    l.nativeName.toLowerCase().contains(_search) ||
                    (languageEnglishNames[l.code] ?? '').toLowerCase().contains(
                      _search,
                    ) ||
                    l.code.contains(_search))
                  ListTile(
                    title: Text(l.nativeName),
                    subtitle: Text(languageEnglishNames[l.code]!),
                    trailing: AppLanguage.instance.code == l.code
                        ? const Icon(Icons.check)
                        : null,
                    onTap: _busy ? null : () => _choose(l.code),
                  ),
            ],
          ),
        ),
      ],
    ),
  );
}
