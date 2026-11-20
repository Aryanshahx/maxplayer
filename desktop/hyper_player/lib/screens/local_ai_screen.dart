import 'package:flutter/material.dart';
import '../player/local_ai.dart';

class LocalAiScreen extends StatefulWidget {
  final String source;
  const LocalAiScreen({super.key, required this.source});
  @override
  State<LocalAiScreen> createState() => _LocalAiScreenState();
}

class _LocalAiScreenState extends State<LocalAiScreen> {
  final job = LocalSpeechJob();
  SpeechModel model = speechModels.first;
  bool translate = false;
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
      final path =
          await job.transcribe(widget.source, model, translate: translate);
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
                            'Whisper ${candidate.name} · ${(candidate.bytes / 1048576).round()} MB model'),
                        subtitle: Text(candidate.name == 'base'
                            ? 'Fastest option; lower accuracy'
                            : candidate.name == 'small'
                                ? 'Better accuracy; more CPU/RAM'
                                : 'Higher capacity; several GB RAM; slow on CPU'),
                        onTap: job.busy
                            ? null
                            : () => setState(() => model = candidate)),
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
