# Android +81 — VPN integration and screenshot-based light-mode fixes

## Apply

Save `update_android_vpn_ui_81.sh` in your existing IntelliJ repository root:

```bash
bash update_android_vpn_ui_81.sh && git add -A && git commit -m "Add Android VPN and fix light-mode input and Discover rendering" && git push
```

`git add -A` includes unrelated pending work; review it before running.
The one script contains the actual files and applies by default. It checks all
before/after hashes before any writes, rejects unknown local edits, makes backups
under `.git/android81-backups/`, rolls back interrupted writes within the running
script, supports `--check`/`--verify`, and is safe to rerun. It does not build,
install packages, commit, push or make Play Console changes.

## Changes visible in the supplied screenshots

- Borderless inputs already inside rounded containers no longer inherit the
  global filled text-field background. This removes the square white inset
  rectangles in Open Stream and Discover/search fields while keeping ordinary
  standalone input styling. Explicit `filled:true` is still honoured.
- Stream title/header hints use a readable secondary text colour, not a faint
  border colour.
- Home Discover poster banner uses a graduated light scrim with much less wash
  at the right, rather than bleaching all posters with near-opaque white.
- Discover year/type/rating metadata has a theme-aware backing panel and solid
  secondary text for contrast against both bright and dark artwork.
- Top 10 rank outlines have a stronger stroke/opacity in light and dark modes.
- Discover splash follows the actual ThemeData brightness, including light
  mode. A single 900 ms ticker advances smoothly and fades out; the old stepped
  percentage, delayed second controller and full-height curtain translation are
  replaced. Reduced-motion users skip the animation. Completion occurs once.

## VPN — included in both Android APK and AAB, as requested

The second Home quick-action page now has VPN in Cloud Storage's previous slot.
All eight quick actions remain. The active eight-feature analytics allowlist
uses `vpn` instead of `cloud`; existing historical Cloud counters are not erased.
The paused admin dashboard is not modified to display the new VPN counter. Old cloud notification deep links are retained
for compatibility; the Cloud Storage tile is no longer shown. The app identity,
release signing, Windows/desktop and existing CI workflows are unchanged.

This is a native VPN integration adapted from the owner's Heaven Browser repo,
not a shortcut to Android settings. Features:

- Cloudflare WARP through the WireGuard GoBackend with the original WARP peer
  handshake/endpoint failover logic. WARP is the initial selected provider.
- OpenVPN country/automatic relay selection using the original Riseup/VPN Gate
  provisioning and the pinned `openvpn_flutter` 2.0.0 engine.
- Search and refresh country entries; displayed country entries are options,
  not evidence that an endpoint in every country is available now.
- Trusted WireGuard/OpenVPN configuration paste/import and profile deletion.
  Executable/nested config directives and oversized imports are rejected.
  Separate username/password files are unsupported: use a certificate profile
  or a trusted inline auth block. VPN Gate's public service credentials apply
  only to built-in profiles, not arbitrary custom accounts.
- Max Player-only split tunnelling is the default, correctly scoped to
  `com.hypertechlabs.maxplayer` for both engines. Full-device routing is an
  explicit toggle. Only one Android VPN may run at a time.
- First-use prominent provider/traffic disclosure before native provisioning,
  followed by Android's own VPN permission when connecting. No auto-connect.
- Connect/disconnect, status, traffic counters and exit-IP/country display.
  The VPN controller is app-scoped so navigating Back does not disconnect it.
- Existing TV focus/OK navigation, light/dark theme and scrolling layouts apply
  to the VPN page. Discovery/server selection does not require touch swipes.

## Safeguards versus blindly copying the source

- No fake success/config/Connected fallback when a native plugin is missing.
- A failed WARP connection does not silently send traffic to a volunteer relay.
- Provider-directory/config retrieval uses HTTPS, not the source's HTTP mirror.
- Built-in VPN Gate TLS configuration is not downgraded to security level 0;
  old/incompatible servers may consequently fail rather than connect insecurely.
- Imported profile/private keys and provider-issued Riseup credentials use
  AES-GCM with an Android Keystore key and no-backup storage. Secure-storage
  failure does not fall back to plaintext preferences; state can be session-only.
- Native parser/engine errors are not echoed with secret configuration lines.
- The disclosure and in-app/web privacy policies identify providers, routing,
  exit-IP check and limitations. VPN profile contents are not analytics fields.

## Important limits and release gates

No real VPN session or native Android build was run in this workspace. Flutter
unit/widget tests and source checks cannot prove native compilation, tunnel
routing, DNS/IPv6 leak behaviour, provider availability or background longevity.
Build and test both artifacts through the existing GitHub Actions workflows:

- APK: https://github.com/Aryanshahx/maxplayer/actions/workflows/android-apk.yml
- AAB: https://github.com/Aryanshahx/maxplayer/actions/workflows/release-aab.yml

New dependency: OpenVPN uses a pinned JitPack native engine; WireGuard comes from
Maven Central. Their representative POMs returned HTTP 200 during inspection,
which is not a guarantee of future artifact availability or a successful build.
Existing Kotlin/Flutter versions, signing keys and CI download-retry behaviour
are preserved. Only Android build number advances to `1.0.1+81`.

Before installing/releasing, check:

1. Google Play VpnService eligibility/declaration and listing disclosure:
   https://support.google.com/googleplay/android-developer/answer/12564964
   A media player is not automatically a permitted VPN exception. Both-artifact
   inclusion was explicitly requested after this risk was explained. Adding VPN
   can lead to Play rejection; this is not an approval guarantee or policy bypass.
2. GPL/third-party distribution/source obligations in `third_party/vpn/NOTICE.md`.
3. Provider terms and the trustworthiness of volunteer/custom exit operators.
   WARP registration uses a third-party API that may change or refuse access.
4. Real device tests: consent decline/accept, Connect/Disconnect on WARP and a
   reachable OpenVPN provider, selecting another provider, app-only vs full-device
   routes, exit address and DNS/IPv6 behaviour, backgrounding, revoking VPN in
   Android settings, competing VPN apps, denied notifications and restarting.
5. Phone light/dark screenshots, Discover splash and TV remote navigation.

No kill switch, anonymity, speed, unlimited data, exact country or always-free
server availability is promised. Normal traffic can resume on disconnect unless
separately blocked by Android's supported Always-on/Block-without-VPN settings.
No new paid hosting or Max Player-operated servers are introduced.
