# ArcBox Makefile
#
# Used by both local dev and CI (release.yml). All build/sign/package logic
# lives here; the workflow only handles CI-specific concerns (secrets,
# artifact upload, notarization credentials, Sparkle signing).
#
# Local:
#   make generate-xcodeproj
#   make bump-arcbox VERSION=v0.4.12
#   make dmg-signed
#
# CI:
#   make prefetch ARCBOX_DIR=arcbox-core SKIP_BUILD=1
#   make dmg-release ARCBOX_DIR=arcbox-core SIGN_IDENTITY="..." NOTARIZE=1

ARCBOX_DIR ?= $(shell cd ../arcbox 2>/dev/null && pwd)
ARCBOX_VERSION := $(strip $(shell /bin/cat arcbox.version))
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null \
	| grep -o '"Developer ID Application: ArcBox, Inc\.[^"]*"' \
	| head -1 | tr -d '"')
SKIP_BUILD ?= 0
SKIP_RUST_BUILD ?= 1
# CI sets these after a separate `make prefetch` so dmg packaging does not
# re-download boot assets / re-run the Xcode embed phase.
SKIP_RESOURCES ?= 0
SKIP_XCODE_EMBED ?= 0
ARCBOX_STAGE_RESOURCES ?= 0
XCODE_AD_HOC_SIGN ?= 1
ARCBOX_PROFILE ?=
ARCBOX_PRODUCT_BUNDLE_IDENTIFIER ?=
ARCBOX_PRODUCT_NAME ?=
ARCBOX_APP_DISPLAY_NAME ?=
DAEMON_SIGN_IDENTITY ?=
REQUIRE_GUEST_AGENTS ?= 0
ARCBOX_HOST_TARGET_DIR ?= $(abspath .build/ArcBoxHost)
ARCBOX_HOST_BIN_DIR ?= $(ARCBOX_HOST_TARGET_DIR)/release
NOTARIZE ?= 0
VERSION ?=
SPARKLE_FEED_URL ?=
PROVISIONING_PROFILE ?=

ABCTL := $(ARCBOX_DIR)/target/release/abctl

.PHONY: build build-runnable build-runnable-rust test resolve format lint lint-xtask test-xtask generate-xcodeproj bump-arcbox verify-arcbox-protobuf build-rust prefetch dmg dmg-signed dmg-release clean help

help:
	@echo "ArcBox build targets:"
	@echo ""
	@echo "  make build          Build the Swift app (Debug, no Rust binaries)"
	@echo "  make build-runnable Build a complete signed ArcBox Dev app for debugging"
	@echo "  make test           Build and run the test suite"
	@echo "  make resolve        Update Package.resolved after a Package.swift change"
	@echo "  make format         Apply swift-format in place"
	@echo "  make lint           Run swift-format --strict and swiftlint (as CI does)"
	@echo "  make lint-xtask     Run cargo fmt --check and clippy -D warnings on xtask/"
	@echo "  make test-xtask     Run the xtask test suite"
	@echo "  make generate-xcodeproj  Regenerate ArcBox.xcodeproj from project.yml"
	@echo "  make bump-arcbox VERSION=vX.Y.Z"
	@echo "                         Update arcbox.version and regenerate protobuf client"
	@echo "  make verify-arcbox-protobuf"
	@echo "                         Verify generated protobuf client matches arcbox.version"
	@echo "  make build-rust     Build arcbox binaries (release)"
	@echo "  make prefetch       Download boot assets + Docker tools"
	@echo "  make dmg            Package unsigned DMG (local testing)"
	@echo "  make dmg-signed     Package signed DMG (Developer ID)"
	@echo "  make dmg-release    Package signed + notarized DMG (CI)"
	@echo "  make clean          Clean build artifacts"
	@echo ""
	@echo "Environment:"
	@echo "  ARCBOX_DIR=$(ARCBOX_DIR)"
	@echo "  SIGN_IDENTITY=$(SIGN_IDENTITY)"
	@echo "  SKIP_RESOURCES=$(SKIP_RESOURCES)"
	@echo "  SKIP_XCODE_EMBED=$(SKIP_XCODE_EMBED)"

## ── Swift app ─────────────────────────────────────────

# devenv's Rust toolchain exports CC/CXX/LD/SDKROOT/MACOSX_DEPLOYMENT_TARGET
# and ~30 NIX_* variables that xcodebuild and SwiftPM cannot use: the nix clang
# rejects -index-store-path, the bare `ld` breaks SPM C-shim links, and the nix
# SDK is older than the Xcode compiler ("no such module 'SwiftShims'"). Each
# nix bump adds more of them, so unsetting the known offenders is a losing
# game — start from an empty environment and allow in only what a build needs.
# On a clean CI runner this changes nothing, which is the point: one recipe
# that behaves the same inside `devenv shell` and on a runner.
#
# devenv also points DEVELOPER_DIR at the nix SDK, which `xcode-select -p`
# echoes back — so dropping it is what restores the real Xcode. To pin a
# specific Xcode, pass XCODE_DEVELOPER_DIR=... (a separate name, so the
# poisoned DEVELOPER_DIR cannot leak in through it).
XCODE_DEVELOPER_DIR ?=
XCODE_SIGN_IDENTITY ?=
CURRENT_PROJECT_VERSION ?=
CARGO_BIN_DIR ?= $(dir $(shell command -v cargo 2>/dev/null))
NODE_BIN_DIR ?= $(dir $(shell command -v node 2>/dev/null))
SYSTEM_DEVELOPER_DIR = $(shell /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/xcode-select -p)
SYSTEM_SDKROOT = $(shell /usr/bin/env -i PATH=/usr/bin:/bin DEVELOPER_DIR="$(SYSTEM_DEVELOPER_DIR)" /usr/bin/xcrun --sdk macosx --show-sdk-path)
XCODE_ENV = /usr/bin/env -i \
	HOME="$$HOME" \
	PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
	$(if $(TMPDIR),TMPDIR="$(TMPDIR)") \
	$(if $(USER),USER="$(USER)") \
	$(if $(LANG),LANG="$(LANG)") \
	$(if $(XCODE_DEVELOPER_DIR),DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)")
HOST_RUST_ENV = /usr/bin/env -i \
	HOME="$$HOME" \
	PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$(CARGO_BIN_DIR):$(NODE_BIN_DIR):$(CURDIR)/.devenv/profile/bin" \
	$(if $(TMPDIR),TMPDIR="$(TMPDIR)") \
	$(if $(USER),USER="$(USER)") \
	DEVELOPER_DIR="$(SYSTEM_DEVELOPER_DIR)" \
	SDKROOT="$(SYSTEM_SDKROOT)" \
	MACOSX_DEPLOYMENT_TARGET=15.0 \
	CC=/usr/bin/cc \
	CXX=/usr/bin/c++ \
	AR=/usr/bin/ar \
	RANLIB=/usr/bin/ranlib \
	CARGO_TARGET_DIR="$(ARCBOX_HOST_TARGET_DIR)"

CONFIGURATION ?= Debug
DESTINATION ?= platform=macOS
DERIVED_DATA_PATH ?= .build/DerivedData

# `-skipPackagePluginValidation`/`-skipMacroValidation`: Xcode requires each
# SwiftPM plugin to be trusted interactively before it will run it. That
# consent lives in Xcode's user defaults, so a machine that has never opened
# the project — every CI runner — fails with `Plugin "OpenAPIGenerator" … must
# be enabled before it can be used`. Skipping validation everywhere keeps
# local and CI on the same command.
#
# SKIP_RUST_BUILD=1: the embed phase pulls prebuilt binaries from ../arcbox.
# These targets compile and test Swift; use `make dmg-signed` for a bundle whose
# daemon survives launch (`make dmg` ad-hoc signs it and drops its entitlements).
#
# `-onlyUsePackageVersionsFromResolvedFile`: build the versions in
# Package.resolved or fail. Without it a manifest edit silently re-resolves and
# the build runs against dependencies nobody reviewed, leaving the committed
# lockfile stale. Run `make resolve` after changing any Package.swift.
XCODEBUILD_FLAGS = \
	-project ArcBox.xcodeproj \
	-scheme ArcBox \
	-configuration $(CONFIGURATION) \
	-destination '$(DESTINATION)' \
	-derivedDataPath $(DERIVED_DATA_PATH) \
	-clonedSourcePackagesDirPath .build/SourcePackages \
	-onlyUsePackageVersionsFromResolvedFile \
	-skipPackagePluginValidation \
	-skipMacroValidation \
	$(XCODEBUILD_EXTRA) \
	$(if $(CURRENT_PROJECT_VERSION),CURRENT_PROJECT_VERSION=$(CURRENT_PROJECT_VERSION)) \
	$(if $(XCODE_SIGN_IDENTITY),CODE_SIGN_IDENTITY='$(XCODE_SIGN_IDENTITY)' CODE_SIGN_STYLE=Manual,$(if $(filter 1,$(XCODE_AD_HOC_SIGN)),CODE_SIGN_IDENTITY=-)) \
	SKIP_RUST_BUILD=$(SKIP_RUST_BUILD) \
	ARCBOX_STAGE_RESOURCES=$(ARCBOX_STAGE_RESOURCES) \
	ARCBOX_CARGO_BIN_DIR='$(CARGO_BIN_DIR)' \
	$(if $(NODE_BIN_DIR),ARCBOX_NODE_BIN_DIR='$(NODE_BIN_DIR)') \
	$(if $(ARCBOX_HOST_BIN_DIR),ARCBOX_HOST_BIN_DIR='$(ARCBOX_HOST_BIN_DIR)') \
	$(if $(ARCBOX_HOST_TARGET_DIR),ARCBOX_HOST_TARGET_DIR='$(ARCBOX_HOST_TARGET_DIR)') \
	$(if $(ARCBOX_DIR),ARCBOX_DIR='$(ARCBOX_DIR)') \
	$(if $(ARCBOX_PROFILE),ARCBOX_PROFILE='$(ARCBOX_PROFILE)') \
	$(if $(ARCBOX_PRODUCT_BUNDLE_IDENTIFIER),ARCBOX_PRODUCT_BUNDLE_IDENTIFIER='$(ARCBOX_PRODUCT_BUNDLE_IDENTIFIER)') \
	$(if $(ARCBOX_PRODUCT_NAME),ARCBOX_PRODUCT_NAME='$(ARCBOX_PRODUCT_NAME)') \
	$(if $(ARCBOX_APP_DISPLAY_NAME),ARCBOX_APP_DISPLAY_NAME='$(ARCBOX_APP_DISPLAY_NAME)') \
	$(if $(DAEMON_SIGN_IDENTITY),DAEMON_SIGN_IDENTITY='$(DAEMON_SIGN_IDENTITY)') \
	$(if $(ARCHS),ARCHS=$(ARCHS))

build:
	$(XCODE_ENV) xcodebuild build $(XCODEBUILD_FLAGS)

build-runnable:
	@actual_commit=$$(/usr/bin/git -C "$(ARCBOX_DIR)" rev-parse HEAD) || exit 1; \
	expected_commit=$$(/usr/bin/git -C "$(ARCBOX_DIR)" rev-parse "$(ARCBOX_VERSION)^{commit}") || exit 1; \
	if [ "$$actual_commit" != "$$expected_commit" ]; then \
		echo "ERROR: ARCBOX_DIR must be checked out at $(ARCBOX_VERSION)." >&2; \
		echo "  Run ./script/build_and_run.sh to use the isolated compatible runtime." >&2; \
		exit 1; \
	fi; \
	if [ -n "$$(/usr/bin/git -C "$(ARCBOX_DIR)" status --porcelain --untracked-files=normal)" ]; then \
		echo "ERROR: ARCBOX_DIR has tracked or untracked source changes." >&2; \
		exit 1; \
	fi
	@if [ -z "$(SIGN_IDENTITY)" ]; then \
		echo "ERROR: No ArcBox Developer ID signing identity found." >&2; \
		exit 1; \
	fi
	@if [ -z "$(CARGO_BIN_DIR)" ]; then \
		echo "ERROR: cargo is unavailable. Enter 'devenv shell' first." >&2; \
		exit 1; \
	fi
	@if [ -z "$(NODE_BIN_DIR)" ]; then \
		echo "ERROR: Node.js is unavailable; it is required to build guest agents." >&2; \
		exit 1; \
	fi
	$(MAKE) build \
		CONFIGURATION=Debug \
		DERIVED_DATA_PATH=.build/DerivedData-Runnable \
		SKIP_RUST_BUILD=0 \
		ARCBOX_STAGE_RESOURCES=1 \
		XCODE_AD_HOC_SIGN=0 \
		ARCBOX_PROFILE=development \
		ARCBOX_PRODUCT_BUNDLE_IDENTIFIER=com.arcboxlabs.desktop.dev \
		ARCBOX_PRODUCT_NAME=ArcBox \
		ARCBOX_APP_DISPLAY_NAME='ArcBox Dev' \
		ARCBOX_HOST_TARGET_DIR='$(ARCBOX_HOST_TARGET_DIR)' \
		ARCBOX_HOST_BIN_DIR='$(ARCBOX_HOST_BIN_DIR)' \
		DAEMON_SIGN_IDENTITY='$(SIGN_IDENTITY)'

test:
	$(XCODE_ENV) xcodebuild test $(XCODEBUILD_FLAGS)

# The one command allowed to move Package.resolved. Commit the result with the
# manifest change that motivated it.
resolve:
	$(XCODE_ENV) xcodebuild -resolvePackageDependencies \
		-project ArcBox.xcodeproj \
		-scheme ArcBox \
		-clonedSourcePackagesDirPath .build/SourcePackages

# Feed swift-format the tracked sources rather than walking directories: a
# local `Packages/*/.build/checkouts` holds vendored third-party code that is
# absent on a fresh CI checkout, so `-r Packages/` lints different files (and
# crashes on some of them) depending on where it runs. swiftlint has its own
# excludes in .swiftlint.yml.
SWIFT_SOURCES = git ls-files -z '*.swift'
TOOL = scripts/tool.sh

format:
	$(SWIFT_SOURCES) | xargs -0 $(TOOL) swift-format format -i

lint:
	$(SWIFT_SOURCES) | xargs -0 $(TOOL) swift-format lint --strict
	$(TOOL) swiftlint lint --strict --config .swiftlint.yml

## ── xtask (Rust) ──────────────────────────────────────

# The targets above cover Swift only. xtask owns embedding, signing, and
# packaging, so a regression there breaks releases rather than the app — it
# gets its own gate instead of riding along on `cargo xtask protocol verify`,
# which merely compiles the crate and never runs its tests.
XTASK_MANIFEST = --manifest-path xtask/Cargo.toml

lint-xtask:
	cargo fmt $(XTASK_MANIFEST) -- --check
	cargo clippy $(XTASK_MANIFEST) --all-targets -- -D warnings

test-xtask:
	cargo test $(XTASK_MANIFEST)

## ── Xcode Project ─────────────────────────────────────

generate-xcodeproj:
	$(TOOL) xcodegen generate

## ── ArcBox Protocol ───────────────────────────────────

bump-arcbox:
	@if [ -z "$(VERSION)" ]; then \
		echo "ERROR: VERSION is required, e.g. make bump-arcbox VERSION=v0.4.12" >&2; \
		exit 1; \
	fi
	cargo xtask protocol bump --version "$(VERSION)"

verify-arcbox-protobuf:
	cargo xtask protocol verify

## ── Prerequisites ─────────────────────────────────────

build-runnable-rust:
	@if [ -z "$(ARCBOX_DIR)" ]; then \
		echo "ERROR: arcbox repo not found at ../arcbox" >&2; \
		echo "  Set ARCBOX_DIR=/path/to/arcbox" >&2; \
		exit 1; \
	fi
	@if [ -z "$(SIGN_IDENTITY)" ]; then \
		echo "ERROR: No ArcBox Developer ID signing identity found." >&2; \
		exit 1; \
	fi
	@if [ -z "$(CARGO_BIN_DIR)" ]; then \
		echo "ERROR: cargo is unavailable. Enter 'devenv shell' first." >&2; \
		exit 1; \
	fi
	@if [ -z "$(NODE_BIN_DIR)" ]; then \
		echo "ERROR: Node.js is unavailable; it is required to build guest agents." >&2; \
		exit 1; \
	fi
	$(HOST_RUST_ENV) cargo build \
		--manifest-path "$(ARCBOX_DIR)/Cargo.toml" \
		-p arcbox-cli -p arcbox-helper -p arcbox-daemon \
		--release
	@for binary in abctl arcbox-helper arcbox-daemon; do \
		if [ ! -x "$(ARCBOX_HOST_BIN_DIR)/$$binary" ]; then \
			echo "ERROR: missing host binary: $(ARCBOX_HOST_BIN_DIR)/$$binary" >&2; \
			exit 1; \
		fi; \
		if /usr/bin/otool -L "$(ARCBOX_HOST_BIN_DIR)/$$binary" | /usr/bin/grep -q /nix/store/; then \
			echo "ERROR: $$binary has a non-portable Nix dylib dependency." >&2; \
			exit 1; \
		fi; \
	done
	$(MAKE) -C "$(ARCBOX_DIR)" build-agent

build-rust:
	@if [ -z "$(ARCBOX_DIR)" ]; then \
		echo "ERROR: arcbox repo not found at ../arcbox" >&2; \
		echo "  Set ARCBOX_DIR=/path/to/arcbox" >&2; \
		exit 1; \
	fi
	@if [ -z "$(CARGO_BIN_DIR)" ]; then \
		echo "ERROR: cargo is unavailable. Enter 'devenv shell' first." >&2; \
		exit 1; \
	fi
	$(MAKE) -C "$(ARCBOX_DIR)" build-cli build-helper PROFILE=release
	$(MAKE) -C "$(ARCBOX_DIR)" sign-daemon PROFILE=release
	$(if $(filter 1,$(REQUIRE_GUEST_AGENTS)),,-)$(MAKE) -C "$(ARCBOX_DIR)" build-agent

prefetch:
	@if [ "$(SKIP_BUILD)" != "1" ]; then \
		$(MAKE) build-rust; \
	fi
	@if [ ! -x "$(ABCTL)" ]; then \
		echo "ERROR: abctl not found at $(ABCTL)" >&2; \
		echo "  Run 'make build-rust' or set ARCBOX_DIR" >&2; \
		exit 1; \
	fi
	"$(ABCTL)" boot prefetch
	"$(ABCTL)" docker setup

## ── Package ───────────────────────────────────────────

# Common xtask flags shared by signed packaging targets.
DMG_XTASK_FLAGS = \
	$(if $(filter 1,$(SKIP_RESOURCES)),--skip-resources) \
	$(if $(filter 1,$(SKIP_XCODE_EMBED)),--skip-xcode-embed) \
	$(if $(PROVISIONING_PROFILE),--provisioning-profile "$(PROVISIONING_PROFILE)")

# When SKIP_RESOURCES=1 the caller already ran `make prefetch`; don't re-run it
# as a Make prerequisite (the xtask side is also gated by --skip-resources).
DMG_PREREQS = $(if $(filter 1,$(SKIP_RESOURCES)),,prefetch)

# Unsigned DMG for local testing.
dmg: $(DMG_PREREQS)
	ARCBOX_DIR="$(ARCBOX_DIR)" cargo xtask macos dmg \
		$(if $(filter 1,$(SKIP_RESOURCES)),--skip-resources) \
		$(if $(filter 1,$(SKIP_XCODE_EMBED)),--skip-xcode-embed)

# Signed DMG for local distribution.
dmg-signed: $(DMG_PREREQS)
	@if [ -z "$(SIGN_IDENTITY)" ]; then \
		echo "ERROR: No Developer ID signing identity found." >&2; \
		exit 1; \
	fi
	ARCBOX_DIR="$(ARCBOX_DIR)" \
	$(if $(VERSION),VERSION="$(VERSION)") \
	$(if $(SPARKLE_FEED_URL),SPARKLE_FEED_URL="$(SPARKLE_FEED_URL)") \
	cargo xtask macos dmg --sign "$(SIGN_IDENTITY)" \
		$(DMG_XTASK_FLAGS)

# Signed + notarized DMG for CI release.
dmg-release: $(DMG_PREREQS)
	@if [ -z "$(SIGN_IDENTITY)" ]; then \
		echo "ERROR: No signing identity." >&2; \
		exit 1; \
	fi
	ARCBOX_DIR="$(ARCBOX_DIR)" \
	$(if $(VERSION),VERSION="$(VERSION)") \
	$(if $(SPARKLE_FEED_URL),SPARKLE_FEED_URL="$(SPARKLE_FEED_URL)") \
	cargo xtask macos dmg --sign "$(SIGN_IDENTITY)" \
		$(if $(filter 1,$(NOTARIZE)),--notarize) \
		$(DMG_XTASK_FLAGS)

## ── Cleanup ───────────────────────────────────────────

clean:
	rm -rf .build/ArcBoxHost .build/DerivedData .build/DerivedData-Runnable
	@if [ -n "$(ARCBOX_DIR)" ] && [ -d "$(ARCBOX_DIR)" ]; then \
		cd "$(ARCBOX_DIR)" && rm -rf target/dmg-build target/ArcBox*.dmg; \
	fi
