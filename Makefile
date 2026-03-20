# ArcBox Desktop Development Makefile

ARCBOX_DIR ?= $(shell cd ../arcbox 2>/dev/null && pwd)
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null \
	| grep -o '"Developer ID Application: ArcBox, Inc\.[^"]*"' \
	| head -1 | tr -d '"')

.PHONY: build-rust prefetch build-app dmg dmg-signed clean help

help:
	@echo "ArcBox Desktop build targets:"
	@echo ""
	@echo "  make build-rust     Build arcbox binaries (release)"
	@echo "  make prefetch       Download boot assets + Docker tools"
	@echo "  make build-app      Build .app via xcodebuild (debug)"
	@echo "  make dmg            Package unsigned DMG (local testing)"
	@echo "  make dmg-signed     Package signed DMG (Developer ID)"
	@echo "  make clean          Clean build artifacts"

## ── Prerequisites ─────────────────────────────────────

build-rust:
	@if [ -z "$(ARCBOX_DIR)" ]; then \
		echo "ERROR: arcbox repo not found at ../arcbox" >&2; \
		echo "  Set ARCBOX_DIR=/path/to/arcbox" >&2; \
		exit 1; \
	fi
	cd "$(ARCBOX_DIR)" && cargo build --release -p arcbox-cli -p arcbox-daemon -p arcbox-helper
	@# Sign daemon so prefetch can use Virtualization.framework
	cd "$(ARCBOX_DIR)" && make sign-daemon PROFILE=release

prefetch: build-rust
	"$(ARCBOX_DIR)/target/release/abctl" boot prefetch
	"$(ARCBOX_DIR)/target/release/abctl" docker setup

## ── Build ─────────────────────────────────────────────

build-app:
	xcodebuild build \
		-project ArcBox.xcodeproj \
		-scheme ArcBox \
		-configuration Debug \
		-skipPackagePluginValidation \
		ARCBOX_DIR="$(ARCBOX_DIR)"

## ── Package ───────────────────────────────────────────

dmg: prefetch
	scripts/package-dmg.sh

dmg-signed: prefetch
	@if [ -z "$(SIGN_IDENTITY)" ]; then \
		echo "ERROR: No Developer ID signing identity found." >&2; \
		exit 1; \
	fi
	scripts/package-dmg.sh --sign "$(SIGN_IDENTITY)"

## ── Cleanup ───────────────────────────────────────────

clean:
	rm -rf .build/DerivedData
	cd "$(ARCBOX_DIR)" && rm -rf target/dmg-build target/ArcBox-*.dmg
