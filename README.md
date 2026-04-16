# codlink

Android client for [OpenAI's Codex](https://github.com/openai/codex). Connect to local or remote Codex app-servers, manage threads, and run agentic coding workflows from your phone.

Forked from [dnakov/litter](https://github.com/dnakov/litter); iOS stripped, Android-first.

## Quick Start

```bash
# One-time: sync the upstream Codex submodule + apply local patches
make sync

# Fast dev build for the connected emulator (auto-detects host ABI)
make android-emulator-fast

# Build a debug APK for a real device (arm64-v8a by default)
make android

# Install the debug APK on a connected device and stream logcat
make android-device-run
```

The debug APK is written to `apps/android/app/build/outputs/apk/debug/app-debug.apk`.

## Prerequisites (Linux)

Install these once on the build host:

- **JDK 17** (Temurin 17 recommended): `sudo apt install temurin-17-jdk` or equivalent.
- **Android SDK** with `platform-tools`, `platforms;android-35`, `build-tools;35.0.0`, and an NDK at `ndk;30.0.14904198` (install via `sdkmanager`). Set `ANDROID_SDK_ROOT` (or `ANDROID_HOME`) to the SDK root.
- **Rust via rustup** — do NOT use a distro `rust` package. `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`.
- **cargo-ndk**: `cargo install cargo-ndk --locked`.
- **System packages** for building the vendored `webrtc-audio-processing-sys`:
  `sudo apt install pkg-config libssl-dev libcap-dev clang cmake meson ninja-build`.

Make auto-detects `ANDROID_SDK_ROOT` from `$ANDROID_HOME` or `$HOME/Android/Sdk`, and finds the NDK under `$ANDROID_SDK_ROOT/ndk/*`. Override via `.env` at the repo root if needed.

## Repository Layout

```
apps/android/                Android app (Compose UI, Gradle build)
shared/rust-bridge/
  codex-mobile-client/       Shared Rust client crate + UniFFI surface
  codex-bridge/              Android JNI shim (libcodex_bridge.so)
  codex-tui/                 Optional developer TUI
shared/third_party/codex/    Upstream Codex submodule
patches/codex/               Local patch set applied during builds
tools/scripts/               Helper scripts (sync-codex, build-android-rust, deploy-android-ondevice)
```

## Architecture

One Rust core (`codex-mobile-client`) exposes a UniFFI surface consumed by Kotlin. Platform code stays thin: UI, permissions, notifications, and Android-only services. Session state, streaming, hydration, discovery, SSH, and auth logic live in Rust.

## Make Targets

| Target | Description |
|---|---|
| `make android` | Full Android debug build (default ABI `arm64-v8a`) |
| `make android-emulator-fast` | Host-ABI debug build for the local emulator |
| `make android-emulator-run` | Build + install + launch on a running emulator |
| `make android-device-run` | Build + install + launch on a connected device, streams logcat |
| `make android-release` | Release build, multi-ABI (`arm64-v8a,x86_64`) |
| `make rust-android` | Only cross-compile the Rust JNI libs |
| `make bindings` | Regenerate UniFFI Kotlin bindings |
| `make rust-check` | Host `cargo check` for shared Rust crates |
| `make rust-test` | Host `cargo test` for shared Rust crates |
| `make sync` | Sync Codex submodule + apply patches |
| `make clean` | Wipe Rust + Android build outputs and stamp cache |

Run `make help` for the full list.

## Release APK Signing

For release builds, set these env vars (or pass as Gradle `-P` properties) so the upload signing config activates:

- `CODLINK_UPLOAD_STORE_FILE`
- `CODLINK_UPLOAD_STORE_PASSWORD`
- `CODLINK_UPLOAD_KEY_ALIAS`
- `CODLINK_UPLOAD_KEY_PASSWORD`

If unset, `make android-release` builds an unsigned release APK.
