# Android App

Android client for OpenAI Codex, built on a Rust-first architecture:

- `app`: Android entrypoint/activity (package `com.codlink.app`).
- `core:bridge`: UniFFI-generated bindings plus Android Rust init/bootstrap.

## Runtime Architecture

- Canonical runtime state lives in Rust `AppStore` and is observed from `app/src/main/java/com/codlink/app/state/AppModel.kt`.
- Direct server operations come from the shared Rust `AppClient` surface.
- Discovery uses Android NSD only for mDNS seeds; merge/dedupe/probing live in Rust `DiscoveryBridge`.
- SSH uses Rust `SshBridge`.
- Voice runtime uses Rust store/RPC for realtime state and Android-only code for audio capture/playback, AEC, and services.

## Local Runtime

- `MainActivity` connects the default local server through `ServerBridge.connectLocalServer(...)`.
- There is no separate bundled Codex process in the active app path.
- `codex-bridge` is only the Android bootstrap/JNI shim; `codex-mobile-client` is the runtime surface.

## Build

Prefer the root `Makefile`:

```bash
make android                 # full debug build (arm64-v8a)
make android-emulator-fast   # host-ABI debug build for the local emulator
make android-device-run      # build + install + launch on a connected device
```

Under the hood those targets invoke:

```bash
./tools/scripts/build-android-rust.sh    # cross-compiles Rust JNI libs
apps/android/gradlew -p apps/android :app:assembleDebug
```

Prerequisites:

- Android NDK (set `ANDROID_NDK_HOME` or `ANDROID_NDK_ROOT`; Make auto-detects the latest under `$ANDROID_SDK_ROOT/ndk/*`).
- `cargo-ndk` (`cargo install cargo-ndk --locked`).

## Rust Bridge (Android)

Android loads the Rust shared library `libcodex_bridge.so` through UniFFI init in `core:bridge`. Generated Kotlin bindings live under `shared/rust-bridge/generated/kotlin/` and are consumed directly by `apps/android/core/bridge`.

QA matrix and regression command list: `apps/android/docs/qa-matrix.md`.
