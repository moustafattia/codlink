#!/usr/bin/make -f

SHELL := /bin/bash
.DEFAULT_GOAL := android

# Prefer rustup-managed toolchain over distro/Homebrew Rust for cross-compilation.
# Also include ~/.cargo/bin for cargo-installed tools like cargo-ndk.
RUSTUP_TOOLCHAIN_BIN := $(shell rustup which cargo 2>/dev/null | xargs dirname 2>/dev/null)
CARGO_BIN := $(HOME)/.cargo/bin
ifneq ($(RUSTUP_TOOLCHAIN_BIN),)
  export PATH := $(RUSTUP_TOOLCHAIN_BIN):$(CARGO_BIN):$(PATH)
else ifneq ($(wildcard $(CARGO_BIN)),)
  export PATH := $(CARGO_BIN):$(PATH)
endif

ROOT := $(shell pwd)
STAMPS := $(ROOT)/.build-stamps
RUST_DIR := $(ROOT)/shared/rust-bridge
RUST_TARGET := $(RUST_DIR)/target
SUBMODULE_DIR := $(ROOT)/shared/third_party/codex
ANDROID_DIR := $(ROOT)/apps/android
ANDROID_JNI := $(ANDROID_DIR)/core/bridge/src/main/jniLibs
GENERATED_DIR := $(RUST_DIR)/generated
PATCHES_DIR := $(ROOT)/patches/codex
TOOL_SCRIPTS := $(ROOT)/tools/scripts

CARGO_FEATURES ?=
ANDROID_ABIS ?= arm64-v8a
ANDROID_RUST_PROFILE ?= android-dev
ANDROID_RELEASE_ABIS ?= arm64-v8a,x86_64
HOST_ARCH := $(shell uname -m)
ANDROID_EMULATOR_ABIS ?= $(if $(filter arm64 aarch64,$(HOST_ARCH)),arm64-v8a,x86_64)

# Source local env (credentials, SDK paths) if present — must precede ?= auto-detect
-include .env

AWS_SHARED_CREDENTIALS_FILE ?= $(HOME)/.aws/credentials

define aws_profile_credential
$(strip $(shell PROFILE='$(AWS_PROFILE)' CREDS_FILE='$(AWS_SHARED_CREDENTIALS_FILE)' KEY='$(1)' /bin/bash -lc '\
if [ -n "$$PROFILE" ] && [ -f "$$CREDS_FILE" ]; then \
  awk -F" *= *" -v profile="$$PROFILE" -v key="$$KEY" '\''
    $$0 == "[" profile "]" { in_profile = 1; next } \
    /^\[/ { in_profile = 0 } \
    in_profile && $$1 == key { print $$2; exit }\
  '\'' "$$CREDS_FILE"; \
fi'))
endef

# Auto-detect Android SDK/NDK paths (Linux + macOS defaults, overridable via env or .env).
ANDROID_SDK_ROOT ?= $(or $(ANDROID_HOME),$(wildcard $(HOME)/Android/Sdk),$(wildcard $(HOME)/Library/Android/sdk))
ANDROID_NDK_HOME ?= $(shell ls -d $(ANDROID_SDK_ROOT)/ndk/*/ 2>/dev/null | sort -V | tail -1 | sed 's:/*$$::')
# JAVA_HOME may stay unset on Linux as long as `java` is on PATH; gradle handles the fallback.
ANDROID_ENV := JAVA_HOME='$(JAVA_HOME)' ANDROID_SDK_ROOT='$(ANDROID_SDK_ROOT)' ANDROID_NDK_HOME='$(ANDROID_NDK_HOME)'

# Android app metadata
ANDROID_APK := $(ANDROID_DIR)/app/build/outputs/apk/debug/app-debug.apk
ANDROID_PACKAGE := com.codlink.app
ANDROID_ACTIVITY := com.codlink.app.MainActivity
ANDROID_DEVICE_SERIAL ?=
ANDROID_REINSTALL_ON_SIGNATURE_MISMATCH ?= 1

export ANDROID_SDK_ROOT
export ANDROID_NDK_HOME
export JAVA_HOME

SCCACHE := $(shell command -v sccache 2>/dev/null)
ifneq ($(SCCACHE),)
  ifeq ($(strip $(AWS_ACCESS_KEY_ID)),)
    AWS_ACCESS_KEY_ID := $(call aws_profile_credential,aws_access_key_id)
  endif
  ifeq ($(strip $(AWS_SECRET_ACCESS_KEY)),)
    AWS_SECRET_ACCESS_KEY := $(call aws_profile_credential,aws_secret_access_key)
  endif
  ifeq ($(strip $(AWS_SESSION_TOKEN)),)
    AWS_SESSION_TOKEN := $(call aws_profile_credential,aws_session_token)
  endif
  export RUSTC_WRAPPER := $(SCCACHE)
  ifdef SCCACHE_BUCKET
    export SCCACHE_BUCKET
    export SCCACHE_ENDPOINT
    export SCCACHE_REGION
    export SCCACHE_S3_KEY_PREFIX
    ifneq ($(strip $(AWS_ACCESS_KEY_ID)),)
      export AWS_ACCESS_KEY_ID
    endif
    ifneq ($(strip $(AWS_SECRET_ACCESS_KEY)),)
      export AWS_SECRET_ACCESS_KEY
    endif
    ifneq ($(strip $(AWS_SESSION_TOKEN)),)
      export AWS_SESSION_TOKEN
    endif
    $(info [cache] Using sccache: $(SCCACHE) → s3://$(SCCACHE_BUCKET))
  else
    $(info [cache] Using sccache: $(SCCACHE) (local only))
  endif
endif

DEV_CARGO_ENV := env -u CARGO_INCREMENTAL

PATCH_FILES := \
	$(PATCHES_DIR)/client-controlled-handoff.patch \
	$(PATCHES_DIR)/mobile-code-mode-stub.patch \
	$(PATCHES_DIR)/thread-read-permissions.patch \
	$(PATCHES_DIR)/mobile-shell-snapshot-timeout.patch

BOUNDARY_SOURCES := $(shell find $(RUST_DIR)/codex-mobile-client/src -type f -name '*.rs' 2>/dev/null) \
	$(RUST_DIR)/codex-mobile-client/Cargo.toml

STAMP_SYNC := $(STAMPS)/sync
STAMP_BINDINGS_K := $(STAMPS)/bindings-kotlin

empty :=
space := $(empty) $(empty)
ANDROID_ABIS_SAFE := $(subst $(space),_,$(subst /,_,$(ANDROID_ABIS)))
ANDROID_RUST_PROFILE_SAFE := $(subst /,_,$(ANDROID_RUST_PROFILE))
STAMP_RUST_ANDROID := $(STAMPS)/rust-android-$(ANDROID_RUST_PROFILE_SAFE)-$(ANDROID_ABIS_SAFE)
ANDROID_RUST_SOURCES := $(shell find $(RUST_DIR) \
	-path '*/target' -prune -o \
	-path '*/generated' -prune -o \
	-type f \( -name '*.rs' -o -name 'Cargo.toml' -o -name 'Cargo.lock' -o -name 'build.rs' \) -print 2>/dev/null)

$(shell mkdir -p $(STAMPS))

.PHONY: all android android-fast android-emulator-fast android-emulator-run android-device-run \
	android-release android-debug android-install android-emulator-install \
	rust-android rust-check rust-test rust-host-dev \
	bindings bindings-kotlin \
	sync patch unpatch \
	test test-rust test-android \
	clean clean-rust clean-android \
	rebuild-bindings tui tui-run export-fixture export-fixture-run help

all: android

android: android-fast
android-fast: rust-android android-debug
android-emulator-fast:
	@$(MAKE) android-fast ANDROID_ABIS="$(ANDROID_EMULATOR_ABIS)"

android-emulator-run: android-emulator-fast
	@echo "==> Installing and launching on emulator..."
	@EMU=$$(adb devices | grep '^emulator-' | head -1 | cut -f1) && \
	if [ -z "$$EMU" ]; then echo "ERROR: no emulator found (run one first)"; exit 1; fi && \
	adb -s "$$EMU" install -r $(ANDROID_APK) && \
	adb -s "$$EMU" shell am start -n $(ANDROID_PACKAGE)/$(ANDROID_ACTIVITY)

android-device-run: android-fast
	@echo "==> Installing and launching on connected device..."
	@DEVICE=$${ANDROID_DEVICE_SERIAL:-$$(adb devices | awk -F'\t' 'NR>1 && $$2=="device" && $$1 !~ /^emulator-/ {print $$1; exit}')} && \
	if [ -z "$$DEVICE" ]; then echo "ERROR: no connected Android device found (set ANDROID_DEVICE_SERIAL=<serial> to override)"; exit 1; fi && \
	echo "==> Using device $$DEVICE..." && \
	INSTALL_OUTPUT=$$(adb -s "$$DEVICE" install -r $(ANDROID_APK) 2>&1) && \
	printf '%s\n' "$$INSTALL_OUTPUT" || { \
		status=$$?; \
		printf '%s\n' "$$INSTALL_OUTPUT"; \
		if printf '%s' "$$INSTALL_OUTPUT" | grep -q 'INSTALL_FAILED_UPDATE_INCOMPATIBLE'; then \
			if [ "$(ANDROID_REINSTALL_ON_SIGNATURE_MISMATCH)" = "1" ]; then \
				echo "==> Installed app has a different signing key; uninstalling $(ANDROID_PACKAGE) and retrying..."; \
				adb -s "$$DEVICE" uninstall $(ANDROID_PACKAGE) && \
				adb -s "$$DEVICE" install -r $(ANDROID_APK) || exit $$?; \
			else \
				echo "ERROR: installed app signature does not match this APK. Re-run with ANDROID_REINSTALL_ON_SIGNATURE_MISMATCH=1 to uninstall the existing app and install this build."; \
				exit 1; \
			fi; \
		else \
			exit $$status; \
		fi; \
	} && \
	echo "==> Launching with attached logcat and timestamps (Ctrl+C stops log streaming)..." && \
	adb -s "$$DEVICE" shell am force-stop $(ANDROID_PACKAGE) >/dev/null 2>&1 || true && \
	adb -s "$$DEVICE" shell am start -W -n $(ANDROID_PACKAGE)/$(ANDROID_ACTIVITY) >/dev/null && \
	PID="" && \
	for _ in $$(seq 1 50); do \
		PID=$$(adb -s "$$DEVICE" shell pidof -s $(ANDROID_PACKAGE) 2>/dev/null | tr -d '\r'); \
		if [ -n "$$PID" ]; then break; fi; \
		sleep 0.2; \
	done && \
	if [ -z "$$PID" ]; then echo "ERROR: app launched but no PID found for $(ANDROID_PACKAGE)"; exit 1; fi && \
	echo "==> Streaming logcat for $(ANDROID_PACKAGE) (pid $$PID)..." && \
	adb -s "$$DEVICE" logcat --pid="$$PID" -v time

android-release: ANDROID_RUST_PROFILE=release
android-release: ANDROID_ABIS=$(ANDROID_RELEASE_ABIS)
android-release: rust-android
	@echo "==> Building Android release..."
	@cd $(ANDROID_DIR) && $(ANDROID_ENV) ./gradlew :app:assembleRelease

rust-check:
	@echo "==> cargo check (host, shared crates)..."
	@cd $(ROOT) && $(DEV_CARGO_ENV) cargo check --manifest-path $(RUST_DIR)/Cargo.toml -p codex-mobile-client

rust-test:
	@echo "==> cargo test (host, shared crates)..."
	@cd $(ROOT) && $(DEV_CARGO_ENV) cargo test --manifest-path $(RUST_DIR)/Cargo.toml -p codex-mobile-client --lib

rust-host-dev: rust-check rust-test

rust-android: $(STAMP_RUST_ANDROID)
$(STAMP_RUST_ANDROID): $(STAMP_SYNC) $(STAMP_BINDINGS_K) $(ANDROID_RUST_SOURCES) $(TOOL_SCRIPTS)/build-android-rust.sh Makefile
	@echo "==> Building Rust for Android..."
	@cd $(ROOT) && $(ANDROID_ENV) ANDROID_ABIS="$(ANDROID_ABIS)" ANDROID_RUST_PROFILE="$(ANDROID_RUST_PROFILE)" $(DEV_CARGO_ENV) ./tools/scripts/build-android-rust.sh
	@touch $@

sync: $(STAMP_SYNC)
$(STAMP_SYNC):
	@echo "==> Syncing codex submodule..."
	@$(TOOL_SCRIPTS)/sync-codex.sh --preserve-current
	@touch $@

patch: $(STAMP_SYNC)
	@echo "==> Verifying codex patch set..."
	@$(TOOL_SCRIPTS)/sync-codex.sh --preserve-current

unpatch:
	@echo "==> Reverting codex patches..."
	@for pf in $(PATCH_FILES); do \
		if git -C $(SUBMODULE_DIR) apply --reverse --check "$$pf" >/dev/null 2>&1; then \
			git -C $(SUBMODULE_DIR) apply --reverse "$$pf"; \
		fi; \
	done
	@rm -f $(STAMP_SYNC)

bindings: bindings-kotlin

bindings-kotlin: $(STAMP_BINDINGS_K)
$(STAMP_BINDINGS_K): $(STAMP_SYNC) $(BOUNDARY_SOURCES)
	@echo "==> Generating Kotlin bindings..."
	@cd $(RUST_DIR) && ./generate-bindings.sh
	@touch $@

android-debug:
	@echo "==> Building Android debug..."
	@cd $(ANDROID_DIR) && $(ANDROID_ENV) ./gradlew :app:assembleDebug

android-install: android-debug
	@echo "==> Installing APK to device..."
	@DEVICE=$${ANDROID_DEVICE_SERIAL:-$$(adb devices | awk -F'\t' 'NR>1 && $$2=="device" && $$1 !~ /^emulator-/ {print $$1; exit}')} && \
	if [ -z "$$DEVICE" ]; then echo "ERROR: no connected Android device found (set ANDROID_DEVICE_SERIAL=<serial> to override)"; exit 1; fi && \
	echo "==> Using device $$DEVICE..." && \
	INSTALL_OUTPUT=$$(adb -s "$$DEVICE" install -r $(ANDROID_APK) 2>&1) && \
	printf '%s\n' "$$INSTALL_OUTPUT" || { \
		status=$$?; \
		printf '%s\n' "$$INSTALL_OUTPUT"; \
		if printf '%s' "$$INSTALL_OUTPUT" | grep -q 'INSTALL_FAILED_UPDATE_INCOMPATIBLE'; then \
			if [ "$(ANDROID_REINSTALL_ON_SIGNATURE_MISMATCH)" = "1" ]; then \
				echo "==> Installed app has a different signing key; uninstalling $(ANDROID_PACKAGE) and retrying..."; \
				adb -s "$$DEVICE" uninstall $(ANDROID_PACKAGE) && \
				adb -s "$$DEVICE" install -r $(ANDROID_APK) || exit $$?; \
			else \
				echo "ERROR: installed app signature does not match this APK. Re-run with ANDROID_REINSTALL_ON_SIGNATURE_MISMATCH=1 to uninstall the existing app and install this build."; \
				exit 1; \
			fi; \
		else \
			exit $$status; \
		fi; \
	}

android-emulator-install: android-emulator-fast
	@echo "==> Installing APK to emulator..."
	@EMU=$$(adb devices | grep '^emulator-' | head -1 | cut -f1) && \
	if [ -z "$$EMU" ]; then echo "ERROR: no emulator found"; exit 1; fi && \
	adb -s "$$EMU" install -r $(ANDROID_APK)

test: test-rust test-android

test-rust:
	@echo "==> Running Rust tests..."
	@cd $(ROOT) && $(DEV_CARGO_ENV) cargo test --manifest-path $(RUST_DIR)/Cargo.toml -p codex-mobile-client --lib

test-android:
	@echo "==> Running Android tests..."
	@cd $(ANDROID_DIR) && ./gradlew :app:testDebugUnitTest

clean: clean-rust clean-android
	@rm -rf $(STAMPS)
	@echo "==> Clean complete"

clean-rust:
	@echo "==> Cleaning Rust build artifacts..."
	@rm -rf $(RUST_TARGET)

clean-android:
	@echo "==> Cleaning Android artifacts..."
	@rm -rf $(ANDROID_JNI)/arm64-v8a $(ANDROID_JNI)/x86_64
	@rm -f $(STAMP_BINDINGS_K) $(STAMPS)/rust-android-*
	@cd $(ANDROID_DIR) && ./gradlew clean 2>/dev/null || true

rebuild-bindings:
	@rm -f $(STAMP_BINDINGS_K)
	@$(MAKE) bindings

tui:
	@echo "── Building codex-tui ──"
	cd shared/rust-bridge && cargo build -p codex-tui --release

tui-run:
	@echo "── Running codex-tui ──"
	cd shared/rust-bridge && cargo run -p codex-tui --release

export-fixture:
	@echo "── Building export-fixture ──"
	cd shared/rust-bridge && cargo build -p codex-tui --bin export-fixture --release

export-fixture-run:
	@cd shared/rust-bridge && cargo run -p codex-tui --bin export-fixture --release -- $(ARGS)

help:
	@printf '%s\n' \
		'make android               fast Android dev build (default ABI: arm64-v8a, profile: android-dev)' \
		'make android-emulator-fast fast Android dev build using emulator ABI ($(ANDROID_EMULATOR_ABIS))' \
		'make android-emulator-run  fast emulator build + install + launch on emulator' \
		'make android-device-run    fast Android dev build + install + launch with attached logcat on connected device (override ANDROID_DEVICE_SERIAL)' \
		'make android-release       Android build using release Rust profile and multi-ABI output' \
		'make android-install       build debug APK and install on connected device' \
		'make android-emulator-install build emulator APK and install on emulator' \
		'make rust-android          build Rust JNI libs only' \
		'make bindings              regenerate Kotlin UniFFI bindings' \
		'make sync                  sync codex submodule + apply patches' \
		'make rust-check            host cargo check for shared crates' \
		'make rust-test             host cargo test for shared crates' \
		'make test                  Rust + Android unit tests' \
		'make clean                 wipe Rust + Android build outputs and stamp cache'
