# VPN components and distribution obligations

## Adapted application code

At the repository owner's request, the VPN controller and Android VPN manager
were adapted from:
https://github.com/Aryanshahx/heavenbrowser
commit `d664734b6f05e189928f76a23a4ad05af73eae74`.
Original paths: `lib/features/vpn/vpn_controller.dart` and
`android/app/src/main/java/com/hypertechlabs/heavenbrowser/HeavenVpnManager.java`.
The original repository did not contain a root LICENSE at the inspected commit.
Public visibility alone is not a general reuse licence. The requested adaptation
assumes the owner has rights to that application code; downstream redistribution
must establish the necessary permissions.

Changes include Max Player package/branding/split-tunnel scope, a new disclosure
and player-themed UI, encrypted no-backup credential storage, fail-closed bridge
responses, HTTPS-only provisioning directory fetches, removal of silent
cross-provider fallback and stricter TLS defaults for built-in OpenVPN relays.
The source is shipped in this repository; no remote code installer is used.

## Dependencies

- `openvpn_flutter` 2.0.0: https://pub.dev/packages/openvpn_flutter
  / https://github.com/nizwar/openvpn_flutter
  Its included GPLv3 licence is reproduced in `OPENVPN_FLUTTER_GPLv3.txt`.
  It uses the OpenVPN/ics-openvpn native engine from
  https://github.com/nizwar/openvpn_library pinned by the plugin to
  commit `ccd61bc39b` via JitPack. The engine and its bundled libraries have
  their own licence/source/notice requirements. Retain their upstream notices.
- WireGuard Android tunnel `com.wireguard.android:tunnel:1.0.20260102`:
  https://git.zx2c4.com/wireguard-android/ and
  https://repo.maven.apache.org/maven2/com/wireguard/android/tunnel/1.0.20260102/
  The Android tunnel library's published POM identifies Apache License 2.0.
  Consult upstream COPYING/notices for the Go/native and crypto dependencies.

IMPORTANT: adding a licence file is not by itself full licence compliance.
Before distributing an APK/AAB, review applicable GPL/copyleft, attribution,
corresponding-source and redistribution obligations for the combined work and
all native components. Provide the required source/build information through a
compliant method. This update does not grant rights to third-party code, change
the licence of unrelated app code, or provide a legal compliance certification.

## Providers are separate from software licences

WARP, Riseup, VPN Gate and volunteer/custom servers are third-party services,
not Max Player-operated infrastructure. Their terms/privacy/availability apply.
No affiliation, permission from providers, free-unlimited service, country,
anonymity or performance guarantee is implied by this integration.
