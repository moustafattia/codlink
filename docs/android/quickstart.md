# Android Quickstart

## Prerequisites
- JDK 17
- Android SDK (API 35, build-tools 35.0.0, NDK 30.0.14904198)
- Rust via rustup + `cargo-ndk` (`cargo install cargo-ndk --locked`)
- `meson`, `ninja`, `clang`, `cmake`, `pkg-config`, `libssl-dev`, `libcap-dev`

## Build Steps
1. One-time submodule sync + patches:
   - `make sync`
2. Build Rust JNI libs + Android debug APK:
   - `make android`
3. Or just the app layer (skip Rust rebuild):
   - `apps/android/gradlew -p apps/android :app:assembleDebug`

APK output: `apps/android/app/build/outputs/apk/debug/app-debug.apk`.

## Modules
- `:app` — Compose UI, services, entrypoint (package `com.codlink.app`)
- `:core:bridge` — UniFFI init + JNI loader (`libcodex_bridge.so`)
