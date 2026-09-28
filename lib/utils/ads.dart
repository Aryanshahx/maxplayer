/// MaxPlayer ads — AdMob (Google Mobile Ads) integration.
///
/// v1.0.1+34: DEMO MODE ONLY. The build uses Google's OFFICIAL demo
/// credentials, which serve "Test Ad"-labeled inventory on any device and
/// can never trigger invalid-traffic strikes. The live AdMob IDs land as a
/// two-line swap (here + the manifest meta-data) before the first
/// ad-carrying Play build.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'crash_log.dart';

/// True while the build serves Google's demo inventory. Flips to false in
/// the pre-Play drop that fills in the live IDs below.
const kAdsDemoMode = true;

/// Google's official ANDROID DEMO App ID (must match the manifest
/// meta-data `com.google.android.gms.ads.APPLICATION_ID`). Tilde `~`
/// separates the publisher id from the app id — a SLASH id here crashes
/// the app before any Dart runs (learned the hard way pre-+17).
const kAdsDemoAppId = 'ca-app-pub-3940256099942544~3347511713';

/// Google's official ANDROID DEMO banner unit (slash form IS correct
/// for ad units).
const kAdsDemoBannerUnit = 'ca-app-pub-3940256099942544/6300978111';

/// Live AdMob ids — intentionally EMPTY in demo builds; a live build
/// without these filled falls back to the demo unit rather than emitting
/// a malformed request.
const kAdsLiveBannerUnit = '';

/// The banner unit this build actually requests (pure).
String adsBannerUnitId() {
  if (!kAdsDemoMode && kAdsLiveBannerUnit.isNotEmpty) {
    return kAdsLiveBannerUnit;
  }
  return kAdsDemoBannerUnit;
}

/// Footer banner slot height in logical px (standard AdSize.banner 320x50).
const double kAdBannerHeight = 50;

/// App IDs use the publisher~app tilde form; ad units use publisher/unit
/// slash form (pure guards used by the pin tests).
bool adsLooksLikeAppId(String id) =>
    id.startsWith('ca-app-pub-') && id.contains('~') && !id.contains('/');
bool adsLooksLikeUnitId(String id) =>
    id.startsWith('ca-app-pub-') && id.contains('/') && !id.contains('~');

class MaxAds {
  MaxAds._();
  static bool _initStarted = false;

  /// Lazy + idempotent SDK init. AdMob is contacted ONLY when the first
  /// ad slot mounts — never at app start: the pre-+17 launch-crash class
  /// (init in the cold path) stays retired. Any failure is logged and the
  /// app simply runs without the banner — ads are a garnish, never a
  /// blocker.
  static Future<void> ensureReady() async {
    if (_initStarted) return;
    _initStarted = true;
    try {
      await MobileAds.instance.initialize();
    } catch (e) {
      CrashLog.error('ads.init', e);
    }
  }
}

/// The Library-home footer banner. Reserves ZERO space until an ad is
/// actually in hand (no gray placeholder box), collapses silently on any
/// failure, and disposes its ad with the slot.
class AdBannerSlot extends StatefulWidget {
  const AdBannerSlot({super.key});

  @override
  State<AdBannerSlot> createState() => _AdBannerSlotState();
}

class _AdBannerSlotState extends State<AdBannerSlot> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    await MaxAds.ensureReady();
    if (!mounted) return;
    final ad = BannerAd(
      adUnitId: adsBannerUnitId(),
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, err) {
          CrashLog.crumb('ads.banner_fail', {
            'code': '${err.code}',
            'domain': err.domain,
          });
          ad.dispose();
          if (mounted) setState(() => _ad = null);
        },
      ),
    );
    _ad = ad;
    try {
      await ad.load();
    } catch (e) {
      CrashLog.error('ads.banner_load', e);
    }
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return Center(
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      ),
    );
  }
}
