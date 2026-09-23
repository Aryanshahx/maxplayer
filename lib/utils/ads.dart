import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// v1.0.1+16 — AdMob integration (bottom banner + player-exit interstitial).
///
/// THE APP SHIPS WITH GOOGLE'S PUBLIC TEST IDS so the feature works end to
/// end without credentials. To go live:
///
///   1. AdMob console → Apps → "Max Player" → Ad units → create TWO units:
///        • type **Banner**       → copy its Ad unit ID
///        • type **Interstitial** → copy its Ad unit ID
///      (Those are the two formats the code uses — do NOT create Rewarded
///      or Native units, there is nothing to show them.)
///
///   2. Paste them below into [_prodBannerUnitId] / [_prodInterstitialUnitId]
///      and flip [kUseTestAds] to false.
///
///   3. Put YOUR App ID (AdMob → Apps → App settings →
///      "ca-app-pub-XXXX~YYYY") into
///      android/app/src/main/AndroidManifest.xml where the marker
///      comment says TODO(ads): the test APPLICATION_ID is sitting there.
///
/// Golden rules:
///   • Never tap your own live ads — test ids exist exactly for dev.
///   • The interstitial shows when the video player closes and is capped
///     by a 3-minute cooldown (plus AdMob console frequency capping if you
///     want an even gentler cadence).
/// ─────────────────────────────────────────────────────────────────────────
class MaxAds {
  MaxAds._();

  /// While true: Google's public test ads. Flip to false with YOUR ids.
  static const bool kUseTestAds = true;

  // Google's official demo unit ids (safe to tap).
  static const String _testBannerUnitId =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _testInterstitialUnitId =
      'ca-app-pub-3940256099942544/1033173712';

  // TODO(ads): paste YOUR AdMob ad unit ids here (see header comment).
  static const String _prodBannerUnitId =
      'ca-app-pub-XXXXXXXXXXXXXXXX/BBBBBBBBBB';
  static const String _prodInterstitialUnitId =
      'ca-app-pub-XXXXXXXXXXXXXXXX/IIIIIIIIII';

  static String get bannerUnitId =>
      kUseTestAds ? _testBannerUnitId : _prodBannerUnitId;
  static String get interstitialUnitId =>
      kUseTestAds ? _testInterstitialUnitId : _prodInterstitialUnitId;

  /// The app is Android-only today, and unit tests run on the host VM —
  /// guard everything so no platform channel is ever touched there.
  static bool get supported => !kIsWeb && Platform.isAndroid;

  static bool _scheduled = false;
  static Future<void>? _ready;

  /// Called once from main(). Only SCHEDULES the SDK init for after the
  /// first frame — startup frames must never wait on (or race) ads, and
  /// any plugin failure is swallowed. Ad loaders await [ensureReady] and
  /// only create/load ads once it completes.
  static void init() {
    if (_scheduled || !supported) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ready ??= _doInit();
    });
  }

  /// Every Banner/Interstitial creation awaits this before touching the
  /// SDK — loading an ad before initialize() finished was a crash window.
  static Future<void> ensureReady() {
    if (!supported) return Future<void>.value();
    return _ready ??= _doInit();
  }

  static Future<void> _doInit() async {
    if (!supported) return;
    try {
      await MobileAds.instance.initialize();
    } catch (_) {}
  }
}

/// Slim 320x50 banner: returns an empty box (zero size) until an ad is
/// loaded, so layouts never jump and failures are invisible.
class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (!MaxAds.supported) return;
    // Never load before MobileAds.initialize() has finished (see
    // MaxAds.ensureReady docs) — that race was a startup crash window.
    unawaited(MaxAds.ensureReady().then((_) {
      if (!mounted) return;
      _ad = BannerAd(
        adUnitId: MaxAds.bannerUnitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (mounted) setState(() => _loaded = true);
          },
          onAdFailedToLoad: (ad, error) {
            ad.dispose();
            if (identical(ad, _ad)) _ad = null;
          },
        ),
      )..load();
    }));
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
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}

/// Player-exit interstitial: preloaded while the video plays (so showing
/// is instant), shown at most once per [cooldown] when the player closes.
class ExitInterstitial {
  ExitInterstitial._();

  static InterstitialAd? _ad;
  static bool _loading = false;
  static DateTime _lastShown = DateTime.fromMillisecondsSinceEpoch(0);

  /// Hard cap: even with unlimited inventory, never show more than one
  /// full-screen ad per 3 minutes of app use.
  static const Duration cooldown = Duration(minutes: 3);

  static bool get _onCooldown =>
      DateTime.now().difference(_lastShown) < cooldown;

  /// Kick off a background load. Call when the video player opens.
  static void preload() {
    if (!MaxAds.supported || _ad != null || _loading || _onCooldown) return;
    _loading = true;
    // Same initialize() ordering guarantee as the banner.
    unawaited(MaxAds.ensureReady().then((_) => _loadNow()));
  }

  static void _loadNow() {
    InterstitialAd.load(
      adUnitId: MaxAds.interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loading = false;
          _ad = ad;
        },
        onAdFailedToLoad: (error) {
          _loading = false;
          _ad = null;
        },
      ),
    );
  }

  /// Call from the video player's dispose(). Shows the ad over whatever
  /// screen the user returns to, then preloads the next one.
  static void maybeShow() {
    final ad = _ad;
    if (!MaxAds.supported || ad == null || _onCooldown) return;
    _ad = null;
    _lastShown = DateTime.now();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        preload();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        preload();
      },
    );
    ad.show();
  }
}

