import 'player/frame_preview_decoder.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

// Windows Shell thumbnail provider, local files only. No upload, playback or download.
class LocalThumbnail extends StatefulWidget {
  final String source;
  const LocalThumbnail(this.source, {super.key});
  @override
  State<LocalThumbnail> createState() => _LocalThumbnailState();
}

class _LocalThumbnailState extends State<LocalThumbnail> {
  late Future<String?> image;
  @override
  void initState() {
    super.initState();
    WindowsThumbnails.retain(widget.source);
    image = WindowsThumbnails.get(widget.source);
  }

  @override
  void didUpdateWidget(covariant LocalThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      WindowsThumbnails.release(oldWidget.source);
      WindowsThumbnails.retain(widget.source);
      image = WindowsThumbnails.get(widget.source);
    }
  }

  @override
  void dispose() {
    WindowsThumbnails.release(widget.source);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: FutureBuilder<String?>(
          key: ValueKey(widget.source),
          future: image,
          builder: (context, snapshot) {
            final path = snapshot.data;
            const fallback = ColoredBox(
                color: Color(0xff18181c),
                child: Center(
                    child: Icon(Icons.video_file_outlined,
                        color: Colors.white38, size: 28)));
            return path == null
                ? fallback
                : Image.file(File(path),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (_, error, stack) => fallback);
          }));
}

class WindowsThumbnails {
  static final _visible = <String, int>{};
  static void retain(String source) =>
      _visible.update(source, (count) => count + 1, ifAbsent: () => 1);
  static void release(String source) {
    final count = _visible[source] ?? 0;
    if (count <= 1) {
      _visible.remove(source);
    } else {
      _visible[source] = count - 1;
    }
  }

  static final List<Future<void>> _lanes =
      List.generate(3, (_) => Future.value());
  static int _nextLane = 0;
  static final _fallbackDecoder = FramePreviewDecoder();
  static Future<void> _decoderTail = Future.value();
  static final _failedUntil = <String, DateTime>{};
  static Future<String?> _decodeFallback(String source, String output) {
    final task = _decoderTail.then((_) async {
      if (await File(output).exists()) return output;
      final bytes =
          await _fallbackDecoder.frame(source, const Duration(seconds: 1));
      if (bytes == null || bytes.isEmpty) return null;
      await File(output).writeAsBytes(bytes, flush: true);
      return output;
    });
    _decoderTail = task.then<void>((_) {}, onError: (Object _) {});
    return task;
  }

  static final Map<String, Future<String?>> _pending = {};
  static Future<String?> get(String source) {
    if (!Platform.isWindows ||
        source.startsWith('http://') ||
        source.startsWith('https://')) {
      return Future.value();
    }
    final retryAt = _failedUntil[source];
    if (retryAt != null && DateTime.now().isBefore(retryAt)) {
      return Future.value();
    }
    return _pending.putIfAbsent(source, () {
      final task = _extract(source);
      // Deduplicate concurrent requests, not permanent failures or changed files.
      task.then((result) {
        _pending.remove(source);
        if (result == null && _visible.containsKey(source)) {
          _failedUntil[source] = DateTime.now().add(const Duration(minutes: 2));
        }
        if (_failedUntil.length > 500) {
          _failedUntil.remove(_failedUntil.keys.first);
        }
      }, onError: (Object _) {
        _pending.remove(source);
      });
      return task;
    });
  }

  static Future<String?> _extract(String source) async {
    try {
      final file = File(source);
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) return null;
      final identity =
          '$source|${stat.size}|${stat.modified.millisecondsSinceEpoch}';
      var hash = 2166136261;
      for (final c in identity.codeUnits) {
        hash = ((hash ^ c) * 16777619) & 0xffffffff;
      }
      final directory = Directory(
          '${(await getApplicationCacheDirectory()).path}/hyper_video_thumbnails');
      await directory.create(recursive: true);
      final output = '${directory.path}/${hash.toRadixString(16)}.png';
      if (await File(output).exists()) return output;
      // Look up disk cache BEFORE waiting for a decoder slot. Cached cards
      // must not queue behind slow Shell handlers for unrelated files.
      final lane = _nextLane++ % _lanes.length;
      final previous = _lanes[lane];
      final slot = Completer<void>();
      _lanes[lane] = slot.future;
      await previous;
      try {
        // A rapidly scrolled-away tile must not delay the now-visible grid.
        if (!_visible.containsKey(source)) return null;
        if (await File(output).exists()) return output;
        final encoded =
            base64Encode(utf8.encode(script).expand((b) => [b, 0]).toList());
        final process = await Process.start('powershell.exe', [
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-EncodedCommand',
          encoded
        ], environment: {
          'HYPER_THUMB_SOURCE': file.absolute.path,
          'HYPER_THUMB_OUTPUT': output
        });
        // Drain both pipes while waiting; kill stalled handlers after 15 seconds.
        process.stdout.drain<void>();
        process.stderr.drain<void>();
        final result = await process.exitCode
            .timeout(const Duration(seconds: 5), onTimeout: () {
          process.kill();
          return -1;
        });
        if (result == 0 && await File(output).exists()) return output;
        return await _decodeFallback(source, output);
      } finally {
        slot.complete();
      }
    } catch (_) {
      return null;
    }
  }

  static const script = r'''
$ErrorActionPreference = 'Stop'
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class HyperThumb {
 [StructLayout(LayoutKind.Sequential)] public struct SIZE { public int cx; public int cy; }
 [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
 interface IImage { [PreserveSig] int GetImage(SIZE size, uint flags, out IntPtr bitmap); }
 [DllImport("shell32.dll", CharSet=CharSet.Unicode, PreserveSig=true)] static extern int SHCreateItemFromParsingName(string path, IntPtr bind, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out IImage item);
 [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr obj);
 public static void Save(string source, string output) {
   var guid = new Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"); IImage item;
   Marshal.ThrowExceptionForHR(SHCreateItemFromParsingName(source, IntPtr.Zero, ref guid, out item));
   IntPtr bitmap = IntPtr.Zero;
   try { Marshal.ThrowExceptionForHR(item.GetImage(new SIZE {cx=320,cy=180}, 9, out bitmap));
     using(var image=Image.FromHbitmap(bitmap)) { image.Save(output, ImageFormat.Png); }
   } finally { if(bitmap!=IntPtr.Zero) DeleteObject(bitmap); Marshal.ReleaseComObject(item); }
 }
}
'@
[HyperThumb]::Save($env:HYPER_THUMB_SOURCE, $env:HYPER_THUMB_OUTPUT)
''';
}
