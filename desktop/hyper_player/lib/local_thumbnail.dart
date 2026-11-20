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
    image = WindowsThumbnails.get(widget.source);
  }

  @override
  void didUpdateWidget(covariant LocalThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      image = WindowsThumbnails.get(widget.source);
    }
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
  static Future<void> _tail = Future.value();
  static final Map<String, Future<String?>> _pending = {};
  static Future<String?> get(String source) {
    if (!Platform.isWindows ||
        source.startsWith('http://') ||
        source.startsWith('https://')) {
      return Future.value();
    }
    return _pending.putIfAbsent(source, () {
      final task = _tail.then((_) => _extract(source));
      _tail = task.then<void>((_) {}, onError: (Object _) {});
      // Deduplicate concurrent requests, not permanent failures or changed files.
      task.whenComplete(() => _pending.remove(source));
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
          '${(await getTemporaryDirectory()).path}/hyper_video_thumbnails');
      await directory.create(recursive: true);
      final output = '${directory.path}/${hash.toRadixString(16)}.png';
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
      final result = await process.exitCode.timeout(const Duration(seconds: 15),
          onTimeout: () {
        process.kill();
        return -1;
      });
      return result == 0 && await File(output).exists() ? output : null;
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
