# Android UI/theme update +82

Baseline: upstream `ed2dd16` (+81). Android version: `1.0.1+82`.

- Player top/bottom chrome uses theme-aware 60%-alpha edge tint fading to fully transparent over the picture. Media/subtitles are not recoloured.
- Network Storage selected label/checkmark uses actual fill contrast; global chip defaults and IPTV group overrides are consistent.
- Featured Discover artwork veils become transparent only in light mode; dark-mode veils remain. Neon cyan/purple/pink splash progress returns with a purple counter and the smooth/reduced-motion exit retained.
- Display Settings adds full RGB sliders, hex preview, persisted custom choice and preset reset. Text/control accent adapts at both extremes for readability.
- In-app manual, complete standalone USER_MANUAL.md and all three privacy-policy surfaces updated. Network Storage plaintext local-preference credentials are explicitly distinguished from encrypted VPN secrets.

Apply the embedded guarded script from the existing repository root. Default is apply; `--check` previews compatibility and `--verify` checks installed payload hashes. Unrecognised edits in payload files stop the entire apply before any overwrite. Backups are kept under Git metadata. No dependency install, build, commit or push is performed by the script.

Desktop, signing, Android package identity and both existing APK/AAB workflows are unchanged. VPN implementation from +81 remains intact. Google Play VPN eligibility/declaration and GPL/source-distribution obligations remain unchanged; this UI update does not establish policy approval.

Validation is Flutter/Python/analyzer plus exact script checks only. Android native builds belong in GitHub Actions. No physical-device render or real VPN routing claim is made. After Actions succeeds, check phone dark/light player bars while video is playing, protocol chips, carousel artwork, splash, RGB persistence after restart and Android TV D-pad focus. Check local sharing and VPN independently on actual devices.
