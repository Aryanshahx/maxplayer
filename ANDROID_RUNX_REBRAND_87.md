# Android 1.0.1+87 — RunX Player rename (display name + docs) + social links

Baseline: upstream `1.0.1+86` (commit `c61b918`).
This release renames the human-facing app name from “Max Player” to **RunX Player**
and points the in-app social links at the new Instagram profile and Telegram channel.

Only user-facing naming changed. The package, applicationId, method channels, signing
identity, notification-channel ids and on-device folder names are untouched, so Play
updates, existing installs, private-vault data and already-saved media keep working.

## Changed

| Area | Change |
| --- | --- |
| Launcher / app label | `android:label="RunX Player"` |
| In-app brand | About sheet, home header, welcome screen, manual, permission hint, appearance copy |
| Docs | `README.md`, `USER_MANUAL.md`, `PRIVACY_POLICY.md`, `privacy/index.html`, in-app privacy text |
| Notifications | Push channel display name `RunX Player notices`, description, fallback title; VPN status notification (`RunX Player VPN Status`, channel id **unchanged**) |
| Quick Share | Receiver page `<title>` / `<h1>`, share captions, “RunX Player Receive” copy |
| AI prompts / network titles | Ask-AI + recommender prompts, `X-Title`/`x-title` headers |
| Report mail | subject now `RunX Player — report & feedback` |
| Localisation | all 42 offline catalogs (`assets/i18n/*.json`): brand tokens in **keys and values** replaced together |
| Version | `pubspec.yaml` `1.0.1+86` → `1.0.1+87`; `kAppVersionTag` (stale `1.0.1+79`) → `1.0.1+87` + test expectation |

## Social links (new)

- Instagram: `https://www.instagram.com/runxplayer_official?hvrq=MTR6NjljZGZtZ2NvdA==`
  (constant `kMaxInstagramUrl`, visible handle `@runxplayer_official`).
- Telegram: `https://t.me/runxofficial_channel`, shown on the Discover card as
  `@runxofficial_channel`.
- New **“Join on Telegram”** entry in the ⋮ → *Settings and more* menu, so both socials
  are reachable from the menu (Instagram was already there).
- Tests `test/widget_test.dart` and `test/polish79_test.dart` updated to the new URL/handle.

Telegram note: the channel link you gave still points at the old `maxofficial_channel`
slug. It is wired up as-is — if the channel is renamed to something like `runxplayer_official`,
send the new `t.me/...` link and it is a one-line change.

## Screenshot / cloud copy

The gallery album on disk is still `Pictures/MaxPlayer` and cloud imports still land in
`Movies/MaxPlayer` (renaming those folders would orphan media users already saved). The UI
now says so plainly — “Saved to Gallery (Pictures/MaxPlayer album)”, “could not be written
to the Videos/MaxPlayer album” — instead of claiming a folder the app does not write.

## Deliberately unchanged (technical / persisted identity)

- `applicationId` / namespace `com.hypertechlabs.maxplayer`; `name: maxplayer`;
  `package:maxplayer/...`; `MaxPlayerApp`.
- Method channels `maxplayer/native`, `maxplayer/storage`, `maxplayer/vpn`.
- Notification channel ids `maxplayer_notices`, `maxplayer_vpn_status`; icon `ic_stat_maxplayer`;
  entry point `maxPlayerPushBackground`; temp dir `maxplayer_notice_images`.
- MediaStore folders `Pictures/MaxPlayer`, `Movies/MaxPlayer`, `Music/MaxPlayer`.
- Private-vault salt `maxplayer.vault::` and the vault directory.
- Server-facing UA strings `kMaxPlayerUserAgent` / `MaxPlayer/1.0`.
- `desktop/`, `admin/`, `.github/`, and all historical release notes/scripts.

## Verification

- `dart analyze`: 0 errors, 0 warnings (only pre-existing `deprecated_member_use` infos).
- All 42 i18n files valid JSON, 366 identical keys per locale, 0 remaining old-brand tokens.
- Full Flutter test suite run in serialized batches — all pass.

## Not verified here

No Android build, device run or Play Console action happens in this sandbox. Build APK/AAB via
the existing GitHub Actions workflow and smoke-test: launcher label, notification titles,
About/manual/privacy screens, both social links (menu + Discover cards), one screenshot save
(album must remain `Pictures/MaxPlayer`).
