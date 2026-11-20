import 'package:flutter/material.dart';

enum DesktopInputKind { click, keyboard }

class DesktopInputIllustration extends StatelessWidget {
  final DesktopInputKind kind;
  const DesktopInputIllustration({super.key, required this.kind});
  @override
  Widget build(BuildContext context) => SizedBox(
      height: 110,
      child: Center(
          child: kind == DesktopInputKind.click
              ? Container(
                  width: 56,
                  height: 82,
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .04),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: Colors.white54, width: 2)),
                  child: Column(children: [
                    Container(height: 30, width: 2, color: Colors.white38),
                    Container(
                        width: 5,
                        height: 13,
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4))),
                    const Spacer()
                  ]))
              : Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                      for (final key in ['←', 'Space', '→'])
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white24)),
                            child: Text(key,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 14)))
                    ])));
}
