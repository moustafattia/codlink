# Repository Guidelines

## Project Structure & Module Organization
- `apps/android/app/src/main/java/com/codlink/app/ui/` contains Android Compose shell and screens.
- `apps/android/app/src/main/java/com/codlink/app/state/` contains Android app state, server/session manager, SSH, and websocket transport.
- `apps/android/core/bridge/` contains Android UniFFI bootstrap (Kotlin package `com.codlink.app.core.bridge`).
- `apps/android/app/src/test/java/com/codlink/app/` contains Android unit tests.
- `apps/android/docs/qa-matrix.md` tracks Android QA coverage.
- `shared/rust-bridge/codex-mobile-client/` is the single shared Rust client library consumed by the Android app. It owns the public UniFFI surface, generated upstream RPC coverage, canonical store/reducer state, hydration, discovery, SSH, and shared runtime logic. `MobileClient` is the top-level internal Rust facade.
- `shared/rust-bridge/codex-bridge/` is the Android JNI shim (`libcodex_bridge.so`) that handles CODEX_HOME/TLS bootstrap on app launch.
- `shared/rust-bridge/codex-tui/` is an optional developer TUI for the shared Rust layer.
- `apps/android/core/bridge/.../Rust*.kt` — thin Android bridge files mapping Kotlin to the shared Rust layer. UniFFI Kotlin sources are generated into `shared/rust-bridge/generated/kotlin/` and consumed directly from there; do not maintain copied binding files under Android source roots.
- `shared/third_party/codex/` is the upstream Codex submodule.

## Architecture
- **Android root layout:** `CodlinkAppShell` is the Compose entry; `DefaultCodlinkAppState` maps backend state into UI state.
- **Android state/transport:** the Rust-owned runtime model is canonical; Kotlin does not re-implement shared session/thread/account logic.
- **Android server flow:** discovery seeds come from Android NSD, but discovery merge/probe policy lives in Rust; connection, auth, and thread/account flows go through Rust RPC + store updates.
- **Message rendering:** reasoning/system sections, code block rendering, and inline image handling are all driven by shared Rust hydration.

### Shared Rust Layer
- `codex-mobile-client` is the single public Rust mobile crate.
- `AppStore` is the Rust-owned state surface. It owns snapshots, typed updates, and the small set of truly composite/store-local actions.
- `AppClient` is the public UniFFI client surface for direct server operations and typed results.
- `DiscoveryBridge` and `SshBridge` are separate Rust utility surfaces. Do not move discovery/SSH policy back into Kotlin.
- The Android app uses UniFFI-generated Kotlin plus thin bridge helpers.

## Feature Placement Rules
- Prefer Rust first. If logic is about session state, thread state, streaming, hydration, approvals, auth/account, discovery merge policy, voice transcript/handoff normalization, or status normalization, it belongs in `shared/rust-bridge/codex-mobile-client/`.
- Keep Kotlin thin. Platform code should only own UI, platform persistence, platform permissions, audio/session APIs, notifications, Android services, and render-only projections.
- Do not parse upstream wire-format strings in Kotlin. If a status, event kind, or payload shape matters to the app, expose it as a typed UniFFI enum/record from Rust.
- Do not duplicate merge/reducer/state-machine logic in Kotlin. Shared reconciliation belongs in Rust reducer/store code.
- If shared Rust needs a direct server operation, expose it on `AppClient` with a mobile-owned request/result shape instead of adding a handwritten wrapper on `AppStore`.
- Keep the public UniFFI surface handwritten and narrow. Put reconciliation policy in handwritten Rust reducer/reconcile code.
- `AppStore` should stay minimal: snapshots, subscriptions, and truly composite/store-local actions only. Direct server operations belong on `AppClient`.
- Prefer authoritative updates. Store state should be populated from upstream events first, then targeted refresh/reconcile when upstream events are insufficient. Do not hand-patch platform state after RPC success.
- New boundary types that cross into Kotlin should be UniFFI-safe Rust records/enums. Internal Rust-only state can stay richer and non-UniFFI.
- Generated Rust sources must stay local-only. Use `*.generated.rs` filenames and do not commit generated Rust files; regenerate them via `./shared/rust-bridge/generate-bindings.sh`.

## Where To Implement New Work
- Add or change direct server coverage:
  - update `shared/rust-bridge/codex-mobile-client/src/ffi/client.rs`
  - update `shared/rust-bridge/codex-mobile-client/src/rpc/client_impl.rs` and/or reconciliation code as needed
  - regenerate bindings
- Add canonical runtime state, reducer logic, or reconciliation:
  - `shared/rust-bridge/codex-mobile-client/src/store/`
- Add conversation hydration, typed item shaping, or shared status normalization:
  - `shared/rust-bridge/codex-mobile-client/src/conversation.rs`
  - `shared/rust-bridge/codex-mobile-client/src/conversation_uniffi.rs`
  - `shared/rust-bridge/codex-mobile-client/src/uniffi_shared.rs`
- Add discovery ranking/dedupe/reconciliation:
  - `shared/rust-bridge/codex-mobile-client/src/discovery.rs`
  - `shared/rust-bridge/codex-mobile-client/src/discovery_uniffi.rs`
- Add voice transcript/handoff/shared realtime normalization:
  - `shared/rust-bridge/codex-mobile-client/src/store/voice.rs`
  - reducer/update boundary types in `store/`
- Add Android-only behavior:
  - `apps/android/app/` and `apps/android/core/bridge/`
  - keep those files free of duplicated Rust-owned state/reducer logic

## Drift Guardrails
- Before adding new Kotlin logic, ask: should this live in Rust and be exposed through UniFFI? Usually yes for shared-runtime concerns.
- Before adding a new `String` status field to Kotlin models, ask: should this be a Rust enum instead? Usually yes.
- Before adding a new `AppStore` method, ask: is this a real composite/store action, or should it live on `AppClient` instead?
- Before adding a new platform cache, ask: is this canonical runtime data that should live in the Rust store instead?
- When in doubt, prefer one shared Rust implementation plus a thin Kotlin projection over reimplementing logic in Kotlin.
- Do not push `shared/third_party/codex` as part of normal repo work. Keep submodule edits local-only unless the user explicitly asks for a separate submodule commit/push, and do not assume a top-level `git push` captures dirty submodule contents.

## Dependencies
### Android (Gradle)
- **Compose Material3** — primary Android UI toolkit.
- **Markwon** — Markdown rendering for assistant/system text.
- **JSch** — SSH transport for remote bootstrap flow (being migrated to shared Rust SSH).
- **androidx.security:security-crypto** — encrypted credential storage.
- **Firebase Cloud Messaging** — push notifications.
- **androidx.media3** — audio playback.
- **androidx.glance** — home-screen widget.
### Rust Shared Layer (Cargo)
- **codex-app-server-protocol**, **codex-app-server-client**, **codex-protocol**, **codex-core** — upstream Codex crates.
- **tokio-tungstenite** — async WebSocket transport.
- **russh** — SSH client (shared Rust SSH, replacing JSch).
- **uniffi** — generates Kotlin bindings from Rust.
- **lru**, **base64**, **regex** — utility crates.

## Fresh Checkout Prerequisites (Linux)
Before building on a new Linux machine, verify:
1. JDK 17 installed and available on PATH (or via `JAVA_HOME`).
2. `cargo` and `rustc` come from **rustup**, not a distro package. Cross-compilation targets like `aarch64-linux-android` fail with distro Rust because the rustup toolchain bin is not on PATH. Either uninstall the distro package or ensure `~/.cargo/bin` (or the rustup toolchain bin from `rustup which cargo`) precedes system paths.
3. `cargo install cargo-ndk --locked`.
4. `meson`, `ninja`, `clang`, `cmake`, `pkg-config`, `libssl-dev`, `libcap-dev` installed. Required by `webrtc-audio-processing-sys`.
5. Android SDK with `platform-tools`, `platforms;android-35`, `build-tools;35.0.0`, and `ndk;30.0.14904198`. `sdkmanager --licenses` must have been accepted.
6. `git submodule update --init --recursive` so `shared/third_party/codex` is populated before `make sync` runs.

## Build System
The root `Makefile` is the primary build interface. It orchestrates submodule sync, patching, UniFFI Kotlin binding generation, Rust cross-compilation, and Android Gradle builds — with stamp-file caching in `.build-stamps/` so repeated runs skip completed steps. If `sccache` is installed it is used automatically via `RUSTC_WRAPPER=sccache`.

Incremental policy: dev targets unset `CARGO_INCREMENTAL` (the sccache setup rejects explicit incremental compilation); release targets run with `CARGO_INCREMENTAL=0`.

### Common targets
| Target | Description |
|---|---|
| `make android` | Full Android debug build (default ABI `arm64-v8a`, profile `android-dev`) |
| `make android-emulator-fast` | Host-ABI debug build (`arm64-v8a` on Apple Silicon / ARM Linux, `x86_64` elsewhere) |
| `make android-emulator-run` | Build + install + launch on a running emulator |
| `make android-device-run` | Build + install on connected device, stream logcat |
| `make android-release` | Release build, multi-ABI (`arm64-v8a,x86_64`) |
| `make android-install` | Build debug APK and install on a connected device |
| `make android-emulator-install` | Build emulator APK and install on emulator |
| `make rust-android` | Build Rust JNI `.so` files only |
| `make rust-check` | Host `cargo check` for shared Rust crates |
| `make rust-test` | Host `cargo test` for shared Rust crates |
| `make bindings` | Regenerate UniFFI Kotlin bindings |
| `make sync` | Sync Codex submodule + apply patches |
| `make test` | Run Rust + Android unit tests |
| `make clean` | Remove all build artifacts + stamp cache |

### Cache invalidation
- `make rebuild-bindings` — force-rebuild UniFFI Kotlin bindings.
- `make clean-rust` / `make clean-android` — remove platform-specific artifacts.

### Configuration overrides (env vars)
- `ANDROID_SDK_ROOT` / `ANDROID_NDK_HOME` / `JAVA_HOME` — required for Android builds in bare shells. Defaults probe `$ANDROID_HOME`, `$HOME/Android/Sdk`, and `$ANDROID_SDK_ROOT/ndk/*`.
- `ANDROID_ABIS` — comma- or space-separated ABI list (default `arm64-v8a`).
- `ANDROID_RUST_PROFILE` — Rust profile used for the JNI build (default `android-dev`).
- `ANDROID_DEVICE_SERIAL` — `adb -s <serial>` override for `android-device-run` / `android-install`.

### Individual scripts (called by Make, can also be run standalone)
- `./tools/scripts/sync-codex.sh` — sync codex submodule + apply patches
- `./tools/scripts/build-android-rust.sh` — cross-compile Rust JNI libs for Android via `cargo-ndk`
- `./tools/scripts/deploy-android-ondevice.sh` — build + install + launch on a real device
- `./shared/rust-bridge/generate-bindings.sh` — generate UniFFI Kotlin bindings

## Autonomous Debugging Runbook
- Prefer the fast lane for local iteration before release lanes: `make android-emulator-fast`.
- For Android emulator debugging, build with `make android-emulator-fast`, install with `adb -e install -r apps/android/app/build/outputs/apk/debug/app-debug.apk`, then launch with `adb -e shell am start -n com.codlink.app/com.codlink.app.MainActivity`.
- Verify an emulator is visible with `adb devices -l` before running `android-emulator-run`.
- Mobile logs: use Logcat and normal Rust `tracing` output. No collector or spool directory.

## Coding Style & Naming Conventions
- Kotlin style follows standard Android/Kotlin conventions: 4-space indentation, `UpperCamelCase` types, `lowerCamelCase` members.
- Dark theme: pure `Color.black` backgrounds, `#00FF9C` accent, monospaced font throughout.
- Keep concurrency boundaries explicit (coroutines scopes, `Dispatchers.Main`) and avoid cross-scope mutable state.
- Group Android files by module (`app/ui`, `app/state`, `core/bridge`).
- No repository-local formatter config is currently committed; keep formatting consistent with existing files.

## Testing Guidelines
- Android tests: place unit tests under `apps/android/app/src/test/java/`.
- Android test command: `cd apps/android && ./gradlew :app:testDebugUnitTest`.
- Keep `apps/android/docs/qa-matrix.md` updated when QA scope changes.

## Commit & Pull Request Guidelines
- Use concise, imperative commit subjects with optional scope (example: `bridge: retry initialize handshake`).
- PRs should include: purpose, key changes, verification steps (commands/device), and screenshots for UI changes.
