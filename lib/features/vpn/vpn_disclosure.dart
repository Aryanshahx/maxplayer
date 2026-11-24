import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_language.dart';

/// v1.0.1+88 — Google Play VpnService "prominent disclosure".
///
/// Play requires every app that uses `android.permission.BIND_VPN_SERVICE`
/// to show, in-app, why the VpnService is needed and which personal/sensitive
/// data it handles — before the tunnel is started. This is the single screen
/// that satisfies that requirement; the reviewer's screen recording shows it.
///
/// Shown once before the first connection. Two exits:
///   * "Agree and connect" — remembers the consent and starts the tunnel.
///   * "Not now"          — returns to the VPN screen without connecting.
class VpnDisclosure {
  static const String prefsKey = 'vpn.disclosureV1.accepted';

  /// True when the user already accepted the disclosure on this install.
  static Future<bool> accepted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(prefsKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> remember() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefsKey, true);
    } catch (_) {
      // Best effort: worst case the disclosure is shown again next time.
    }
  }

  /// Shows the disclosure when [force] is false and the user has not yet
  /// agreed. Returns true when the caller may start the connection.
  static Future<bool> ensureAccepted(
    BuildContext context, {
    bool force = false,
  }) async {
    if (!force && await accepted()) return true;
    if (!context.mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => const _VpnDisclosureDialog(),
    );
    if (ok == true) {
      await remember();
      return true;
    }
    return false;
  }

  /// Read-only copy of the disclosure, also used by the VPN screen's
  /// "Why this permission?" link and by the privacy screen.
  static const List<String> points = <String>[
    'RunX Player uses the Android VpnService to route your network traffic '
        'through a VPN server that YOU choose. The VPN starts only after you '
        'tap Connect — it never starts on its own or in the background.',
    'While the VPN is connected, the operator you selected (Cloudflare WARP, '
        'Riseup, VPN Gate or a profile you imported) can see your IP address, '
        'the addresses you connect to and any traffic that is not encrypted. '
        'RunX Player does not operate VPN exit servers.',
    'To keep usage statistics working, the app sends pseudonymous counters '
        '(app opens, feature use, app/device information and a randomly '
        'generated installation ID) to our Firebase database, and asks '
        'api.country.is for the country of your connection IP. The full IP '
        'address is not stored by us. Details are in the privacy policy.',
    'You can disconnect at any time from this screen. Android shows a VPN '
        'key/status icon while a tunnel is active.',
  ];

  const VpnDisclosure();
}

class _VpnDisclosureDialog extends StatelessWidget {
  const _VpnDisclosureDialog();

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return AlertDialog(
      title: const LText('Why RunX Player needs a VPN connection'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final p in VpnDisclosure.points)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 3, right: 8),
                        child: Icon(Icons.circle, size: 6),
                      ),
                      Expanded(
                        child: Text(
                          p,
                          style: const TextStyle(fontSize: 13, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              const Text(
                'By tapping Agree you consent to this use of the Android '
                'VpnService and to the data handling described above.',
                style: TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const LText('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const LText('Agree and connect'),
        ),
      ],
    );
  }
}

/// Reusable link that re-opens the disclosure from the VPN screen.
Future<void> showVpnDisclosureAgain(BuildContext context) async {
  await showDialog<bool>(
    context: context,
    builder: (c) => const _VpnDisclosureDialog(),
  );
}
