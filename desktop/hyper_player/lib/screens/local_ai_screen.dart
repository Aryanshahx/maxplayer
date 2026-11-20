import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../player/local_ai.dart';

const Map<String, String> speechLanguages = {
  'auto': 'Auto-detect',
  'en': 'English',
  'hi': 'Hindi',
  'ur': 'Urdu',
  'ar': 'Arabic',
  'bn': 'Bengali',
  'ta': 'Tamil',
  'te': 'Telugu',
  'pa': 'Punjabi',
  'mr': 'Marathi',
  'gu': 'Gujarati',
  'kn': 'Kannada',
  'ml': 'Malayalam',
  'ne': 'Nepali',
  'es': 'Spanish',
  'fr': 'French',
  'de': 'German',
  'it': 'Italian',
  'pt': 'Portuguese',
  'ru': 'Russian',
  'ja': 'Japanese',
  'ko': 'Korean',
  'id': 'Indonesian',
  'tr': 'Turkish',
  'fa': 'Persian',
  'vi': 'Vietnamese',
  'th': 'Thai',
  'uk': 'Ukrainian',
  'pl': 'Polish',
  'nl': 'Dutch',
  'he': 'Hebrew',
};

class LocalAiScreen extends StatefulWidget {
  final String source;
  const LocalAiScreen({super.key, required this.source});
  @override
  State<LocalAiScreen> createState() => _LocalAiScreenState();
}

class _LocalAiScreenState extends State<LocalAiScreen> {
  final job = LocalSpeechJob();
  SpeechModel model = speechModels.first;
  bool translate = false, karaokeStyle = false;
  String language = 'auto';
  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      model = speechModels.firstWhere(
          (m) => m.name == prefs.getString('hyper.ai.model'),
          orElse: () => speechModels.first);
      final saved = prefs.getString('hyper.ai.language') ?? 'auto';
      language = speechLanguages.containsKey(saved) ? saved : 'auto';
      translate = prefs.getBool('hyper.ai.translate') ?? false;
      karaokeStyle = prefs.getBool('hyper.ai.karaokeStyle') ?? false;
    });
  }

  String? output, error;
  @override
  void dispose() {
    job.cancel();
    /* job may still be cleaning up; no disposed notifier */ super.dispose();
  }

  Future<void> start() async {
    setState(() {
      error = null;
      output = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('hyper.ai.model', model.name);
      await prefs.setString('hyper.ai.language', language);
      await prefs.setBool('hyper.ai.translate', translate);
      await prefs.setBool('hyper.ai.karaokeStyle', karaokeStyle);
      final path = await job.transcribe(widget.source, model,
          translate: translate, language: language, karaokeStyle: karaokeStyle);
      if (mounted) setState(() => output = path);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: job,
      builder: (context, _) => PopScope(
            canPop: !job.busy,
            child: Scaffold(
                appBar: AppBar(
                    title: const Text('AI subtitles · local & optional')),
                body: ListView(padding: const EdgeInsets.all(24), children: [
                  const Text(
                      'No media is uploaded. On first use, download whisper.cpp, FFmpeg and the selected multilingual model. The tool archives add about 92 MB of downloads plus extracted files. Downloads stay on this PC for reuse. These are third-party open-source tools; additional disk space is required. Larger is not always faster or more accurate for every language.'),
                  const SizedBox(height: 16),
                  for (final candidate in speechModels)
                    ListTile(
                        leading: Icon(model == candidate
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off),
                        title: Text(
                            '${candidate.name == 'base-q5_1' ? 'Fast (recommended)' : 'Whisper ${candidate.name}'} · ${(candidate.bytes / 1048576).round()} MB model'),
                        subtitle: Text(candidate.name == 'base-q5_1'
                            ? 'Android fast option · quantized model'
                            : candidate.name == 'base'
                                ? 'Fastest option; lower accuracy'
                                : candidate.name == 'small'
                                    ? 'Better accuracy; more CPU/RAM'
                                    : 'Higher capacity; several GB RAM; slow on CPU'),
                        onTap: job.busy
                            ? null
                            : () => setState(() => model = candidate)),
                  DropdownButtonFormField<String>(
                      initialValue: language,
                      key: ValueKey(language),
                      decoration:
                          const InputDecoration(labelText: 'Speech language'),
                      items: speechLanguages.entries
                          .map((e) => DropdownMenuItem(
                              value: e.key, child: Text(e.value)))
                          .toList(),
                      onChanged: job.busy
                          ? null
                          : (v) => setState(() => language = v ?? 'auto')),
                  SwitchListTile(
                      title: const Text('Karaoke style'),
                      subtitle: const Text(
                          'Word-by-word flow subtitles, like Android'),
                      value: karaokeStyle,
                      onChanged: job.busy
                          ? null
                          : (v) => setState(() => karaokeStyle = v)),
                  SwitchListTile(
                      title: const Text('Translate speech to English'),
                      subtitle: const Text(
                          'Off: transcribe in the detected source language'),
                      value: translate,
                      onChanged: job.busy
                          ? null
                          : (v) => setState(() => translate = v)),
                  Text(job.status),
                  if (job.busy) const LinearProgressIndicator(),
                  if (error != null)
                    SelectableText(error!,
                        style: const TextStyle(color: Colors.orange)),
                  if (!job.busy)
                    FilledButton(
                        onPressed: start,
                        child: const Text(
                            'Download if needed & generate subtitles')),
                  if (job.busy)
                    TextButton(
                        onPressed: job.cancel, child: const Text('Cancel job')),
                  if (output != null)
                    FilledButton.icon(
                        onPressed: () => Navigator.pop(context, output),
                        icon: const Icon(Icons.subtitles),
                        label: const Text('Load generated subtitles')),
                  const SizedBox(height: 16),
                  const Text(
                      'Licences: whisper.cpp MIT; Whisper models MIT; FFmpeg downloaded GPL build. Downloads are SHA-256 checked before use. If a release changes, verification fails rather than executing unverified tools. Processing time and accuracy depend on your PC and recording. You can close the page after cancelling/completion.'),
                ])),
          ));
}
