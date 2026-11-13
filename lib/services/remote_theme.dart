import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_analytics.dart';
import 'country_lookup.dart';

const themeDefaults = <String, String>{
  'background': '#060608',
  'surface': '#101013',
  'surfaceAlt': '#18181C',
  'border': '#26262C',
  'textPrimary': '#F5F6F8',
  'textSecondary': '#9296A0',
  'accent': '#FFFFFF',
  'danger': '#E5484D',
};

Map<String, dynamic> validateTheme(Map<String, dynamic> value) {
  if (value.keys.any(
    (k) => ![
      'schemaVersion',
      'name',
      'palette',
      'decoration',
      'headerLabel',
      'visuals',
    ].contains(k),
  )) {
    throw const FormatException('Unknown theme property');
  }
  if (![1, 2].contains(value['schemaVersion']) ||
      value['name'] is! String ||
      (value['name'] as String).trim().isEmpty ||
      (value['name'] as String).length > 60) {
    throw const FormatException('Invalid theme name/version');
  }
  final palette = value['palette'];
  if (palette is! Map ||
      palette.keys.any((k) => !themeDefaults.containsKey(k)) ||
      palette.values.any(
        (v) => v is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v),
      )) {
    throw const FormatException(
      'Palette must contain supported #RRGGBB colours',
    );
  }
  final merged = {...themeDefaults, ...Map<String, String>.from(palette)};
  Color colour(String k) =>
      Color(int.parse('FF${merged[k]!.substring(1)}', radix: 16));
  final light = colour('textPrimary').computeLuminance(),
      dark = colour('background').computeLuminance();
  if ((light + 0.05) / (dark + 0.05) < 4.5) {
    throw const FormatException(
      'Use a dark background and readable light text (4.5:1)',
    );
  }
  final decoration = value['decoration'] ?? 'none';
  if (!['none', 'christmas', 'diwali'].contains(decoration)) {
    throw const FormatException('Unknown decoration');
  }
  final header = value['headerLabel'] ?? '';
  if (header is! String || header.length > 80) {
    throw const FormatException('Header label is too long');
  }
  final visuals = value['visuals'] ?? <String, dynamic>{};
  if (visuals is! Map ||
      visuals.keys.any(
        (k) =>
            !['buttonStyle', 'cardStyle', 'background', 'rounded'].contains(k),
      ) ||
      ![
        'plain',
        'snowcap',
        'lantern',
      ].contains(visuals['buttonStyle'] ?? 'plain') ||
      ![
        'plain',
        'ribbon',
        'goldOutline',
      ].contains(visuals['cardStyle'] ?? 'plain') ||
      !['none', 'snow', 'stars'].contains(visuals['background'] ?? 'none') ||
      !['soft', 'pill'].contains(visuals['rounded'] ?? 'soft') ||
      (value['schemaVersion'] == 1 && visuals.isNotEmpty)) {
    throw const FormatException(
      'Invalid visuals; use schemaVersion 2 and supported visual presets',
    );
  }
  return {
    'schemaVersion': value['schemaVersion'],
    if (value['schemaVersion'] == 2)
      'visuals': Map<String, dynamic>.from(visuals),
    'name': (value['name'] as String).trim(),
    'palette': merged,
    'decoration': decoration,
    'headerLabel': header,
  };
}

class RemoteTheme extends ChangeNotifier {
  RemoteTheme._();
  static final instance = RemoteTheme._();
  Map<String, dynamic>? current;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  Color colour(String key) => Color(
    int.parse(
      'FF${((current?['palette'] as Map?)?[key] as String? ?? themeDefaults[key]!).substring(1)}',
      radix: 16,
    ),
  );
  bool get active => current != null;
  Future<void> loadCache() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(
        'remote.theme.v1',
      );
      if (raw != null) {
        current = validateTheme(Map<String, dynamic>.from(jsonDecode(raw)));
      }
    } catch (_) {
      current = null;
    }
  }

  String country = '';
  Map<String, dynamic>? _legacy, _audience;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _audienceSubscription;
  bool _countryBusy = false;
  Future<void> _resolveCountry() async {
    if (_countryBusy) return;
    _countryBusy = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      country =
          prefs.getString('theme.country.code') ??
          prefs.getString('aa.ipCountryV1.code') ??
          '';
      final at = prefs.getInt('theme.country.at') ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - at > 86400000) {
        final fresh = await lookupIpCountry();
        if (fresh.isNotEmpty) {
          country = fresh;
          await prefs.setString('theme.country.code', fresh);
          await prefs.setInt(
            'theme.country.at',
            DateTime.now().millisecondsSinceEpoch,
          );
        }
      }
      await _apply();
    } finally {
      _countryBusy = false;
    }
  }

  Future<void> _apply() async {
    try {
      final next = selectThemePublication(_audience, country, _legacy);
      current = next;
      final prefs = await SharedPreferences.getInstance();
      if (next == null) {
        await prefs.remove('remote.theme.v1');
      } else {
        await prefs.setString('remote.theme.v1', jsonEncode(next));
      }
      notifyListeners();
    } catch (_) {
      /* malformed publication keeps last-known-good */
    }
  }

  Future<void> start() async {
    if (!AppAnalytics.ready.value) return;
    unawaited(_resolveCountry());
    _subscription ??= FirebaseFirestore.instance
        .collection('appConfig')
        .doc('theme')
        .snapshots()
        .listen(
          (s) {
            _legacy = s.data();
            unawaited(_apply());
          },
          onError: (Object _) {
            _subscription = null;
          },
        );
    _audienceSubscription ??= FirebaseFirestore.instance
        .collection('appConfig')
        .doc('themeAudience')
        .snapshots()
        .listen(
          (s) {
            _audience = s.data();
            unawaited(_apply());
          },
          onError: (Object _) {
            _audienceSubscription = null;
          },
        );
  }
}

class SeasonalBanner extends StatelessWidget {
  const SeasonalBanner({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: RemoteTheme.instance,
    builder: (context, _) => _content(context),
  );

  Widget _content(BuildContext context) {
    final theme = RemoteTheme.instance.current;
    if (theme == null) return const SizedBox.shrink();
    final decoration = theme['decoration'];
    final label = theme['headerLabel'] as String;
    if (label.isEmpty && decoration == 'none') return const SizedBox.shrink();
    final symbol = decoration == 'christmas'
        ? '❄'
        : decoration == 'diwali'
        ? '✦'
        : '';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RemoteTheme.instance.colour('surfaceAlt'),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RemoteTheme.instance.colour('accent')),
      ),
      child: Row(
        children: [
          if (symbol.isNotEmpty)
            Text(
              '$symbol  ',
              style: TextStyle(
                fontSize: 24,
                color: RemoteTheme.instance.colour('accent'),
              ),
            ),
          Expanded(
            child: Text(
              label.isEmpty ? theme['name'] as String : label,
              style: TextStyle(
                color: RemoteTheme.instance.colour('textPrimary'),
              ),
            ),
          ),
          if (symbol.isNotEmpty)
            Text(
              symbol,
              style: TextStyle(color: RemoteTheme.instance.colour('accent')),
            ),
        ],
      ),
    );
  }
}

/// Country overrides are appearance preferences, never authorization boundaries.
Map<String, dynamic>? selectThemePublication(
  Map<String, dynamic>? audience,
  String country,
  Map<String, dynamic>? legacy,
) {
  final slots = audience?['slots'];
  final publication = slots is Map
      ? (slots[country] ?? slots['ALL'] ?? legacy)
      : legacy;
  if (publication == null || publication['enabled'] != true) return null;
  return validateTheme(Map<String, dynamic>.from(publication['theme'] as Map));
}
