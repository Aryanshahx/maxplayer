# Android +86 — direct VPN controls and theme-aware gesture illustrations

Baseline: upstream +85. Version 1.0.1+86.

The VPN screen opens directly to the connection controls without an in-app agreement page, instruction/disclaimer text, information dialog, relay-warning paragraph or import helper warning. Opening it does not initiate a new VPN connection or request permission. Connect retains the existing Android/native permission path; denial and actual connection failures are not hidden. A previously active app-scoped connection is not stopped merely by opening/leaving the page. Existing Android approval can mean the operating system does not show its prompt again.

No native VPN/permission implementation, configuration validation, encryption, provider selection, automatic-connect behaviour, signing, desktop or APK/AAB workflows are changed. Privacy policy and manual are synchronised to stop claiming there is a separate app consent screen. Existing privacy/provider information remains in the normal app Privacy policy, not on the VPN controls screen.

Distribution note: the Android permission dialog is not a substitute for Google Play's separate prominent-disclosure/consent obligations. This requested UI does not establish Play compliance or provider-terms compliance; review those obligations before publishing. A disclosure in a privacy policy alone may not satisfy Play requirements. No approval guarantee is made.

Gesture diagrams are vector paintings, not screenshots. Their phone body/screen, guide strokes, labels, play marker, brightness symbol and badge foreground now derive from an immutable theme palette. Light mode uses a light simulated screen and dark high-contrast strokes; dark mode remains dark. Filled accent badges choose a contrasting foreground. Repainting also tracks palette changes, fixing a theme-only switch when the accent is unchanged. The shared fix applies to onboarding's last page and the in-app manual. Video content and the +85 white player controls remain unchanged.

Run the single embedded .sh from the existing repository root. Default apply; --check preflight; --verify installed payload hashes. Unrecognised local edits stop before overwrite, with backups under Git metadata. The script does not build, commit or push. Native Android builds belong in existing GitHub Actions. Physical-device rendering and real VPN routing/permission handling require a device test.
