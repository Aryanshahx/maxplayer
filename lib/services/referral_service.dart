import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_analytics.dart';

/// v1.0.1+58: Refer & Earn — recommend Max Player, unlock AD-FREE time.
///
/// RULES (compiled in, also shown in the invite sheet):
///   share your code -> a friend installs + claims it -> counts as 1 referral
///   every [kReferralsPerReward] referrals -> [kRewardDays] days ad-free,
///   stacking (6 friends = 1 year).
///
/// Privacy: install profiles hold NO personal data beyond an anonymous
/// install id + the referral graph.
class ReferralService {
  ReferralService._();
  static final ReferralService instance = ReferralService._();

  static const int kReferralsPerReward = 3;
  static const int kRewardDays = 182; // ~6 months
  static const String kPlayUrl =
      'https://play.google.com/store/apps/details?id=com.hypertechlabs.maxplayer';

  static const _kInstallId = 'ref.installId';
  static const _kCode = 'ref.code';
  static const _kReferrer = 'ref.myReferrer';
  static const _kCount = 'ref.count';
  static const _kAdFreeUntilMs = 'ref.adFreeUntilMs';
  static const _kPrompted = 'ref.claimPrompted';

  /// Live flag consulted by every ad surface.
  static final ValueNotifier<bool> adsFree = ValueNotifier<bool>(false);

  String? installId;
  String? code;
  String? referrer;
  int referralCount = 0;
  DateTime? adFreeUntil;
  bool _inited = false;

  SharedPreferences? _prefs;

  /// Generate a fresh human-friendly code: "MAX-XXXX" (no confusables).
  static String generateCode([Random? rng]) {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final r = rng ?? Random.secure();
    final tail = List.generate(
      4,
      (_) => alphabet[r.nextInt(alphabet.length)],
    ).join();
    return 'MAX-$tail';
  }

  int get pendingToNextReward =>
      kReferralsPerReward - (referralCount % kReferralsPerReward);

  String get adFreeUntilLabel {
    final d = adFreeUntil;
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  /// Fire after runApp(). Loads local state instantly (ads-free flag works
  /// OFFLINE), then syncs with Firestore if configured. Never throws.
  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    try {
      final p = _prefs = await SharedPreferences.getInstance();
      installId = p.getString(_kInstallId);
      if (installId == null) {
        installId = _newInstallId();
        await p.setString(_kInstallId, installId!);
      }
      code = p.getString(_kCode) ?? _mintAndSaveCode();
      referrer = p.getString(_kReferrer);
      referralCount = p.getInt(_kCount) ?? 0;
      final ms = p.getInt(_kAdFreeUntilMs);
      if (ms != null) adFreeUntil = DateTime.fromMillisecondsSinceEpoch(ms);
      _refreshAdsFreeFlag();
    } catch (_) {
      /* local failure: referral stays cosmetic */
    }
    unawaited(_syncRemote());
  }

  String _newInstallId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  String _mintAndSaveCode() {
    final c = generateCode();
    final f = _prefs?.setString(_kCode, c);
    if (f != null) unawaited(f);
    return c;
  }

  void _refreshAdsFreeFlag() {
    final d = adFreeUntil;
    adsFree.value = d != null && d.isAfter(DateTime.now());
  }

  FirebaseFirestore? get _db =>
      AppAnalytics.ready.value ? FirebaseFirestore.instance : null;

  Future<void> _syncRemote() async {
    await AppAnalytics.instance.ensureInit();
    final db = _db;
    final id = installId;
    final myCode = code;
    if (db == null || id == null || myCode == null) return;
    try {
      // register profile + code lookup (merge = only fills gaps)
      final batch = db.batch()
        ..set(db.collection('users').doc(id), {
          'installId': id,
          'code': myCode,
          'referralsCount': referralCount,
          'lastSeen': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true))
        ..set(db.collection('codes').doc(myCode), {
          'uid': id,
        }, SetOptions(merge: true));
      await batch.commit();
      // pull latest counters from cloud (owner may have been credited)
      final snap = await db.collection('users').doc(id).get();
      final data = snap.data();
      if (data != null) {
        await _acceptRemoteCount((data['referralsCount'] as num?)?.toInt());
        final until = (data['adFreeUntil'] as Timestamp?)?.toDate();
        if (until != null &&
            (adFreeUntil == null || until.isAfter(adFreeUntil!))) {
          adFreeUntil = until;
          await _prefs?.setInt(_kAdFreeUntilMs, until.millisecondsSinceEpoch);
          _refreshAdsFreeFlag();
        }
      }
    } catch (_) {
      /* offline — local state is enough till next launch */
    }
  }

  Future<void> _acceptRemoteCount(int? remote) async {
    if (remote == null || remote <= referralCount) return;
    referralCount = remote;
    await _prefs?.setInt(_kCount, remote);
  }

  /// Claim a friend's code (one-time, self-claims rejected).
  /// Returns a human message for the UI snackbar.
  Future<String?> claimCode(String raw) async {
    final theirs = raw.trim().toUpperCase();
    if (theirs.isEmpty) return 'Enter a code first';
    if (theirs == code) return 'That one is yours 🙂';
    if (referrer != null) return 'You already claimed a code earlier';
    final db = _db;
    if (db == null) {
      return 'Offline — connect once and try again';
    }
    final id = installId;
    if (id == null) return 'Not ready yet, reopen the app';
    try {
      return await db.runTransaction<String?>((tx) async {
        final codeDoc = await tx.get(db.collection('codes').doc(theirs));
        final owner = codeDoc.data()?['uid'] as String?;
        if (!codeDoc.exists || owner == null) return 'Code not found';
        if (owner == id) return 'That one is yours 🙂';
        final myRef = db.collection('users').doc(id);
        final me = await tx.get(myRef);
        if ((me.data()?['myReferrer'] as String?) != null) {
          return 'You already claimed a code earlier';
        }
        // +1 to owner + public board + remember locally
        tx.update(db.collection('users').doc(owner), {
          'referralsCount': FieldValue.increment(1),
        });
        tx.set(db.collection('referral_board').doc(owner), {
          'count': FieldValue.increment(1),
        }, SetOptions(merge: true));
        tx.set(myRef, {
          'myReferrer': theirs,
          'claimedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return null; // success signal
      });
    } catch (_) {
      return 'Invalid code';
    }
  }

  /// LOCAL mirror of a successful claim (called by the UI after it gets the
  /// success message).
  Future<void> markClaimed(String theirs) async {
    referrer = theirs;
    await _prefs?.setString(_kReferrer, theirs);
    AppAnalytics.instance.log('referral_claimed');
  }

  /// Whether we still owe the user the first-launch "have a code?" prompt.
  bool get shouldPromptForCode =>
      referrer == null && !(_prefs?.getBool(_kPrompted) ?? false);

  Future<void> markPrompted() async {
    await _prefs?.setBool(_kPrompted, true);
  }

  String get shareText =>
      'I use Max Player — plays every format, AI subtitles, movie '
      'discovery. Install it and enter my code $code in "Invite & Earn" and '
      'we both progress to AD-FREE: $kPlayUrl';
}
