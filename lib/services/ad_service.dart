import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// v1.0.1+50: AdMob wiring — SAFE BY CONSTRUCTION.
///
/// - TEST ad unit ids below; swap the two constants + the manifest
///   meta-data value before a release build.
/// - init NEVER blocks startup: main() calls [safeInit] unawaited,
///   AFTER runApp(). Devices without Play services simply never load
///   an ad — no black screen, no crash.
/// - Every failure degrades to invisible: the banner slot collapses to
///   zero height, the interstitial just proceeds — an ad can never
///   block navigation.
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  /// Google TEST banner unit (never pays out — safe while testing).
  static const String kTestBannerId = 'ca-app-pub-3940256099942544/6300978111';

  /// Google TEST interstitial unit.
  static const String kTestInterstitialId =
      'ca-app-pub-3940256099942544/1033173712';

  /// SWAP THESE to your real AdMob unit ids before release.
  static const String bannerId = kTestBannerId;
  static const String interstitialId = kTestInterstitialId;

  /// Becomes true once the Google Mobile Ads SDK is initialized — the
  /// banner slot listens to this before attempting any load.
  final ValueNotifier<bool> ready = ValueNotifier<bool>(false);

  bool _initializing = false;
  bool _initialized = false;

  InterstitialAd? _interstitial;
  bool _interstitialLoading = false;

  /// Frequency cap: at most one interstitial per app session so testing
  /// never becomes nag-ware.
  static const int kMaxInterstitialsPerSession = 1;
  int _interstitialShownThisSession = 0;

  /// Fire after runApp(). Never throws, never blocks startup.
  Future<void> safeInit() async {
    if (_initialized || _initializing) return;
    _initializing = true;
    try {
      await MobileAds.instance.initialize();
      _initialized = true;
      ready.value = true;
      _preloadInterstitial();
    } catch (e) {
      // No Play services / offline — the app just stays ad-free.
      debugPrint('AdMob init skipped (no Play services?): $e');
    } finally {
      _initializing = false;
    }
  }

  void _preloadInterstitial() {
    if (_interstitialLoading || _interstitial != null) return;
    _interstitialLoading = true;
    InterstitialAd.load(
      adUnitId: interstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitial = ad;
          _interstitialLoading = false;
        },
        onAdFailedToLoad: (error) {
          debugPrint('Interstitial failed to load: $error');
          _interstitialLoading = false;
        },
      ),
    );
  }

  /// Shows the interstitial (if ready and under the session cap), then
  /// ALWAYS calls [proceed] — user navigation is never hostage to an ad.
  void showInterstitialThenProceed(VoidCallback proceed) {
    final ad = _interstitial;
    if (!_initialized ||
        ad == null ||
        _interstitialShownThisSession >= kMaxInterstitialsPerSession) {
      proceed();
      return;
    }
    _interstitial = null;
    _interstitialShownThisSession++;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _preloadInterstitial();
        proceed();
      },
      onAdFailedToShowFullScreenContent: (a, error) {
        a.dispose();
        _preloadInterstitial();
        proceed();
      },
    );
    try {
      ad.show();
    } catch (_) {
      proceed();
    }
  }
}

/// v1.0.1+50: bottom banner slot. Collapses to zero height until an ad
/// is actually loaded, and stays collapsed forever on failure — it can
/// never cover content with a dead placeholder.
class CineBannerSlot extends StatefulWidget {
  const CineBannerSlot({super.key});

  @override
  State<CineBannerSlot> createState() => _CineBannerSlotState();
}

class _CineBannerSlotState extends State<CineBannerSlot> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    AdService.instance.ready.addListener(_maybeLoad);
    _maybeLoad();
  }

  void _maybeLoad() {
    if (!mounted || _loaded || _failed || _ad != null) return;
    if (!AdService.instance.ready.value) return;
    final ad = BannerAd(
      adUnitId: AdService.bannerId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (a, error) {
          debugPrint('Banner failed to load: $error');
          a.dispose();
          _failed = true;
          _ad = null;
        },
      ),
    );
    _ad = ad;
    ad.load();
  }

  @override
  void dispose() {
    AdService.instance.ready.removeListener(_maybeLoad);
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return Container(
      color: Colors.black,
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
