# Shared Scripts

- `build-android-rust.sh` — cross-compiles the shared Rust libs for Android via `cargo-ndk` and writes JNI `.so` files into `apps/android/core/bridge/src/main/jniLibs/`.
- `deploy-android-ondevice.sh` — builds Rust JNI libs, assembles the `onDevice` debug APK, installs on a target device (`--serial`/`ANDROID_SERIAL`), and launches the app.
- `sync-codex.sh` — syncs the upstream `shared/third_party/codex` submodule and applies the in-tree patches under `patches/codex/`.
- `load-sccache-aws-creds.sh` — sourced by other scripts to optionally enable `sccache` with R2 backend for Rust caching.
