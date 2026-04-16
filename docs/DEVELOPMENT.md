# Development Guide

## Prerequisites (Linux)

- **JDK 17** (Temurin 17 recommended).
- **Android SDK** with:
  - `platform-tools`
  - `platforms;android-35`
  - `build-tools;35.0.0`
  - `ndk;30.0.14904198`
  - Accepted licenses (`sdkmanager --licenses`).
  - `ANDROID_SDK_ROOT` or `ANDROID_HOME` pointing at the SDK root.
- **Rust via rustup** (NOT a distro `rust` package — it will shadow rustup cross-compilation targets):

  ```bash
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  rustup target add aarch64-linux-android x86_64-linux-android
  cargo install cargo-ndk --locked
  ```

- **System libs** required by the vendored `webrtc-audio-processing-sys`:

  ```bash
  sudo apt install pkg-config libssl-dev libcap-dev clang cmake meson ninja-build
  ```

- **`sccache`** (optional but recommended):

  ```bash
  cargo install sccache --locked
  ```

  Make auto-detects sccache and routes compilation through it when present.

## Connect a Dev Machine to Codlink Over SSH

Make Codex sessions running on another machine visible in the Codlink app.

1. Enable SSH on the host machine.
2. Verify SSH and Codex binaries from a non-interactive SSH shell:

   ```bash
   ssh <user>@<host> 'echo ok'
   ssh <user>@<host> 'command -v codex || command -v codex-app-server'
   ```

   If the second command prints nothing, install Codex and/or fix shell PATH startup files.

3. In Codlink: keep phone and host on the same LAN (or same Tailnet). In Discovery, tap a host showing `codex running` to connect directly, or tap an `SSH` host and enter credentials.

4. Fallback — run app-server manually on the host and add the server manually in Codlink:

   ```bash
   codex app-server --listen ws://0.0.0.0:8390
   ```

   Then in the app choose `Add Server` and enter `<host-ip>` + `8390`.

5. Thread/session listing is `cwd`-scoped. If expected sessions are missing, choose the same working directory used when those sessions were created.

## Codex Submodule + Patches

Upstream Codex is vendored as a submodule at `shared/third_party/codex`.

Current local patch set (applied by `tools/scripts/sync-codex.sh`):

- `patches/codex/client-controlled-handoff.patch`
- `patches/codex/mobile-code-mode-stub.patch`
- `patches/codex/thread-read-permissions.patch`
- `patches/codex/mobile-shell-snapshot-timeout.patch`

Additional patches (not auto-applied):

- `patches/codex/android-vendored-openssl.patch`
- `patches/codex/realtime-transcript-deltas.patch`

Sync/apply (idempotent):

```bash
./tools/scripts/sync-codex.sh
```

Pass `--recorded-gitlink` to reset the submodule to the commit recorded in the superproject.

## Build the Rust Bridge

```bash
./tools/scripts/build-android-rust.sh     # arm64-v8a by default
ANDROID_ABIS="arm64-v8a,x86_64" ./tools/scripts/build-android-rust.sh
```

## Build and Run Android

```bash
make android                    # full Android debug build
make android-emulator-fast      # host-ABI debug build for the local emulator
make android-emulator-run       # build + install + launch on a running emulator
make android-device-run         # build + install on a connected device, stream logcat
cd apps/android && ./gradlew :app:testDebugUnitTest     # run unit tests
```

APK output: `apps/android/app/build/outputs/apk/debug/app-debug.apk`.

## Release APK Signing

Set these env vars (or `-P` Gradle properties) for a signed release build:

- `CODLINK_UPLOAD_STORE_FILE`
- `CODLINK_UPLOAD_STORE_PASSWORD`
- `CODLINK_UPLOAD_KEY_ALIAS`
- `CODLINK_UPLOAD_KEY_PASSWORD`

Then:

```bash
make android-release
```

If unset, Gradle builds an unsigned release APK.
