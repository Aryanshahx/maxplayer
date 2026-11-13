# 1.0.1+71 — restore metrics and bottom navigation

- Fixed bottom navigation: Overview, Send, Countries, Errors, Settings. Visible after admin sign-in on desktop/mobile; Settings opens its disclosure panel. Existing sidebar remains on large screens.
- Restores App opens, Videos played, Install registrations, Streams opened and IPTV plays alongside the eight feature metrics in the time-series selector and exact-numbers table.
- Restores Videos played, Streams opened and IPTV plays to the What gets used comparison, retaining all eight feature screen-open counters. Play-failure and ad-impression cards remain removed.
- Compare like-for-like carefully: a screen open and a playback event measure different things, and percentages do NOT represent unique users.
- Daily install registrations start on +71: only a first launch whose local installCounted flag is false records a daily install increment. An existing +70 installation upgrading to +71 is NOT counted as a new install. Clearing app data/reinstalling can create another registration. Previous all-time totals cannot be reconstructed into dates.
- The installs chart explicitly warns that earlier dates are unavailable, not verified zero. Missing daily fields use the existing chart's zero visual baseline; use the caveat rather than treating pre-+71 dates as actual zero registrations. Totals are best-effort telemetry, not Google Play verified downloads.
- Existing privacy disclosures describe install registrations and aggregate tracking. No new geolocation provider, notification UI, permission or personal profile is added.
- Install the +71 CI APK for new daily registration events. The panel changes appear after Pages deployment. Firebase rules/secrets/toolchain remain unchanged.

## Not implemented by this update
Remote seasonal theme control and app-internal notification destinations require a one-time app/config/sender/admin implementation. The current notification link opens an external HTTPS URL, not an internal screen. Do not enter maxplayer:// URLs into the current HTTPS-only composer; they are not supported by it.

A future seasonal-theme implementation should use a small versioned allowlisted configuration, cached last-known-good/default theme, validated HTTPS assets, start/end/expiry, preview/publish/revert and compatible app versions. It can change supported colour tokens/assets/presets, not download executable code or invent new app screens. All hard-coded app styling must first be migrated to those tokens if truly app-wide theming is wanted.

Future notification destinations should use a finite screen enum plus validated optional IDs, transported through the protected queue and sender. Route after startup/permission/auth prerequisites. Private destinations must retain PIN/biometric protection. Unknown targets fall back to home. Cold/warm/foreground/background taps all need real-device testing. Existing external HTTPS linking remains separate.

## Verification
No Dart analyzer issues; 265 Flutter tests and 19 JavaScript tests passed. Chromium checks with mocked services covered restored selector/comparison labels, bottom-nav Settings on mobile, login persistence, sending/current status, PDF, IP country separation and app-error filtering. Production Firebase and actual device registration require integration testing. No local APK build; existing GitHub CI is used.
