# Android APK/AAB dependency-download resilience

## The reported failure

The APK log explicitly shows Maven Central HTTP 429 (Too Many Requests), reached through Plugin Portal redirects while resolving Kotlin plugin/BOM artifacts for Flutter's included Gradle build. This is a dependency transport/rate-limit error, not evidence of a Dart compilation error, incorrect signing password or a missing Kotlin release. Changing Kotlin versions, reintroducing ads or regenerating signing keys would not address it.

The earlier repository init script was installed by the AAB workflow only. The APK workflow did not install it. This update fixes that coverage gap and uses the same setup in both workflows.

## Changes

- Both APK and AAB workflows install the Gradle init script before the Android build.
- Plugin-resolution repositories try the Google-hosted Maven Central mirror at `https://maven-central.storage-download.googleapis.com/maven2` before direct Maven Central; Google Maven and Plugin Portal remain available. Only plugin resolution is changed; no untrusted HTTP repository, TLS bypass or global repository injection into Flutter's project repositories is added.
- The affected Kotlin 2.2.20 BOM was fetched from the mirror and direct Maven Central during preparation: both returned 200 and the same SHA-256 `3c6d469e915fbb3096ac4cb8c2f46c79d027c3c590e658a10688a1571eb578d8`. This checks one representative file, not every dependency or permanent mirror availability.
- Both workflows cache Gradle `modules-2` downloads and wrapper distributions. Cache keys include the toolchain Gradle files, wrapper properties, pubspec lock and repository init script. Gradle/Kotlin DSL compilation caches with SDK-specific absolute paths are not shared.
- Both build steps use a shared Python helper. It attempts at most 3 builds, with 60–80 seconds and 180–200 seconds of backoff for recognized temporary dependency-download errors (429/502/503/504 or limited connection/timeout failures).
- Gradle workers are limited to 2 and parallel project execution disabled for these build invocations, reducing simultaneous dependency requests.
- No `flutter clean`, cache deletion or `--refresh-dependencies` is performed on retry. Successful downloads within a run remain reusable. Actions cache can also help later successful runs; an entirely failed run is not guaranteed to save its new cache.
- Ordinary compilation, missing symbols, bad signing passwords, 404 dependencies and TLS certificate failures are not treated as transient download retries. Exhausted retries leave the job FAILED with the real output visible.
- Each build job has a 45-minute overall limit. Flutter build uses `--no-pub` because workflows already run pub get, analyze and tests first. API definitions are passed as argument-array elements, not echoed by the wrapper.
- The AAB signing restore, signature check, strict final ad-free manifest check, pinned bundletool checksum, cleanup and artifact upload remain in place.

No app source, version code, package ID, signing credentials, Android permissions, Dart dependencies, admin backend or Windows workflow changes are included. There is no need to increase the app version for this CI-only correction.

## Validation and limits

Python tests simulate successful retries, permanent failure after 3 attempts, non-retryable compile/signing/404/TLS errors, preserved Gradle options and wrapper output without logging supplied secret values. Existing ad-free manifest verifier tests remain enabled. Both workflow YAML documents, setup ordering and preservation of the AAB validation steps were checked. The delivery script is checked on a clean baseline copy for apply/verify/repeat-apply/conflicting-edit behaviour.

No native APK/AAB build was run locally. The next GitHub Actions run is the actual end-to-end validation. Public repositories and mirrors can still be unavailable or rate-limit requests; this update adds mitigation, not a promise that downloads can never fail. If all attempts still show 429, wait 5–10 minutes and rerun the failed job rather than repeatedly starting parallel builds.

## Apply, commit and push

Place `update_android_ci_download_retry.sh` in the existing IntelliJ repository root:

```sh
bash update_android_ci_download_retry.sh &&
git add -A &&
git commit -m "Make Android APK and AAB dependency downloads resilient to rate limits" &&
git push
```

`git add -A` stages all pending work; review unrelated changes first. The script defaults to apply; --check / --apply / --verify are also supported, with backups and baseline-hash checks. It does not run a local Android build or modify GitHub settings/secrets.

Use the NEW commit's runs:
- APK: https://github.com/Aryanshahx/maxplayer/actions/workflows/android-apk.yml
- AAB: https://github.com/Aryanshahx/maxplayer/actions/workflows/release-aab.yml

Rerunning an old failed commit uses its old workflow. It can succeed if a temporary rate limit has cleared, but it does not include this mitigation.
