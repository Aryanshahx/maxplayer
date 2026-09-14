import 'package:shared_preferences/shared_preferences.dart';

/// First-run onboarding state (Welcome → How to use → Video player guide).
///
/// The flow is shown exactly once, the first time the app opens after
/// install. Users can replay it anytime from the home ⋮ menu → "Replay
/// guide" (that path does not touch this flag — only the automatic
/// first-run trigger is suppressed).
class Onboarding {
  Onboarding._();

  static const _kSeen = 'onboarding.seen';

  static Future<bool> hasSeen() async =>
      (await SharedPreferences.getInstance()).getBool(_kSeen) ?? false;

  static Future<void> markSeen() async =>
      (await SharedPreferences.getInstance()).setBool(_kSeen, true);
}
