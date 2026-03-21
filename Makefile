# ArcBox Desktop Makefile
#
# Used by both local dev and CI (release.yml). All build/sign/package logic
# lives here; the workflow only handles CI-specific concerns (secrets,
# artifact upload, notarization credentials, Sparkle signing).
#
# Local:
#   make dmg-signed
#
# CI:
#   make prefetch ARCBOX_DIR=arcbox-core SKIP_BUILD=1
#   make dmg-release ARCBOX_DIR=arcbox-core SIGN_IDENTITY="..." NOTARIZE=1

ARCBOX_DIR ?= $(shell cd ../arcbox 2>/dev/null && pwd)
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null \
	| grep -o '"Developer ID Application: ArcBox, Inc\.[^"]*"' \
	| head -1 | tr -d '"')
SKIP_BUILD ?= 0
NOTARIZE ?= 0
VERSION ?=
SPARKLE_FEED_URL ?=

ABCTL := $(ARCBOX_DIR)/target/release/abctl

.PHONY: build-rust prefetch build-app dmg dmg-signed dmg-release clean help

help:
	@echo "ArcBox Desktop build targets:"
	@echo ""
	@echo "  make build-rust     Build arcbox binaries (release)"
	@echo "  make prefetch       Download boot assets + Docker tools"
	@echo "  make build-app      Build .app via xcodebuild (debug)"
	@echo "  make dmg            Package unsigned DMG (local testing)"
	@echo "  make dmg-signed     Package signed DMG (Developer ID)"
	@echo "  make dmg-release    Package signed + notarized DMG (CI)"
	@echo "  make clean          Clean build artifacts"
	@echo ""
	@echo "Environment:"
	@echo "  ARCBOX_DIR=$(ARCBOX_DIR)"
	@echo "  SIGN_IDENTITY=$(SIGN_IDENTITY)"

## ── Prerequisites ─────────────────────────────────────

build-rust:
	@if [ -z "$(ARCBOX_DIR)" ]; then \
		echo "ERROR: arcbox repo not found at ../arcbox" >&2; \
		echo "  Set ARCBOX_DIR=/path/to/arcbox" >&2; \
		exit 1; \
	fi
	cd "$(ARCBOX_DIR)" && cargo build --release -p arcbox-cli -p arcbox-daemon -p arcbox-helper
	cd "$(ARCBOX_DIR)" && make build-agent
	cd "$(ARCBOX_DIR)" && make sign-daemon PROFILE=release

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

## ── Build ─────────────────────────────────────────────

build-app:
	xcodebuild build \
		-project ArcBox.xcodeproj \
		-scheme ArcBox \
		-configuration Debug \
		-skipPackagePluginValidation \
		ARCBOX_DIR="$(ARCBOX_DIR)"

## ── Package ───────────────────────────────────────────

# Unsigned DMG for local testing.
dmg: prefetch
	ARCBOX_DIR="$(ARCBOX_DIR)" scripts/package-dmg.sh

# Signed DMG for local distribution.
dmg-signed: prefetch
	@if [ -z "$(SIGN_IDENTITY)" ]; then \
		echo "ERROR: No Developer ID signing identity found." >&2; \
		exit 1; \
	fi
	ARCBOX_DIR="$(ARCBOX_DIR)" \
	$(if $(VERSION),VERSION="$(VERSION)") \
	$(if $(SPARKLE_FEED_URL),SPARKLE_FEED_URL="$(SPARKLE_FEED_URL)") \
	scripts/package-dmg.sh --sign "$(SIGN_IDENTITY)"

# Signed + notarized DMG for CI release.
dmg-release: prefetch
	@if [ -z "$(SIGN_IDENTITY)" ]; then \
		echo "ERROR: No signing identity." >&2; \
		exit 1; \
	fi
	ARCBOX_DIR="$(ARCBOX_DIR)" \
	$(if $(VERSION),VERSION="$(VERSION)") \
	$(if $(SPARKLE_FEED_URL),SPARKLE_FEED_URL="$(SPARKLE_FEED_URL)") \
	scripts/package-dmg.sh --sign "$(SIGN_IDENTITY)" $(if $(filter 1,$(NOTARIZE)),--notarize)

## ── Cleanup ───────────────────────────────────────────

clean:
	rm -rf .build/DerivedData
	@if [ -n "$(ARCBOX_DIR)" ] && [ -d "$(ARCBOX_DIR)" ]; then \
		cd "$(ARCBOX_DIR)" && rm -rf target/dmg-build target/ArcBox-*.dmg; \
	fi
