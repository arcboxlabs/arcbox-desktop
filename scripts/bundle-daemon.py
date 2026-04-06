#!/usr/bin/env python3
"""
Build a minimal .app bundle around the arcbox-daemon binary.

This gives the daemon its own Contents/embedded.provisionprofile so that
AMFI can validate restricted entitlements (com.apple.vm.networking) on
the user's machine — the same approach OrbStack uses for its helper.

Usage:
    bundle-daemon.py <daemon-binary> <output-dir> [options]

Example (dev):
    bundle-daemon.py target/release/arcbox-daemon .build/DerivedData/.../Frameworks

Example (release):
    bundle-daemon.py arcbox-daemon /tmp/dmg-build/ArcBox.app/Contents/Frameworks \
        --provisioning-profile /tmp/embedded.provisionprofile \
        --sign "Developer ID Application: ArcBox, Inc. (XXXXX)" \
        --entitlements ../arcbox/bundle/arcbox.entitlements \
        --version 1.18.4
"""
from __future__ import annotations

import argparse
import os
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

BUNDLE_ID = "com.arcboxlabs.desktop.daemon"
BUNDLE_NAME = "ArcBox Daemon"
EXECUTABLE_NAME = "com.arcboxlabs.desktop.daemon"


def create_info_plist(bundle_contents: Path, version: str) -> Path:
    """Write a minimal Info.plist into the bundle."""
    info = {
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleExecutable": EXECUTABLE_NAME,
        "CFBundleName": BUNDLE_NAME,
        "CFBundlePackageType": "APPL",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleVersion": version,
        "CFBundleShortVersionString": version,
        "CFBundleSupportedPlatforms": ["MacOSX"],
        "LSUIElement": True,
    }
    plist_path = bundle_contents / "Info.plist"
    with open(plist_path, "wb") as f:
        plistlib.dump(info, f)
    return plist_path


def create_pkginfo(bundle_contents: Path) -> Path:
    """Write PkgInfo (optional but conventional)."""
    pkg_path = bundle_contents / "PkgInfo"
    pkg_path.write_text("APPL????")
    return pkg_path


def codesign(target: Path, identity: str, entitlements: Path | None = None) -> None:
    """Sign a binary or bundle with hardened runtime."""
    cmd = [
        "codesign", "--force", "--options", "runtime",
        "--sign", identity, "--timestamp",
    ]
    if entitlements:
        cmd += ["--entitlements", str(entitlements)]
    cmd.append(str(target))
    subprocess.run(cmd, check=True)


def verify_signature(target: Path, check_entitlements: bool = False) -> bool:
    """Verify code signature. Optionally check for required entitlements."""
    result = subprocess.run(
        ["codesign", "--verify", "--strict", str(target)],
        capture_output=True,
    )
    if result.returncode != 0:
        return False

    if check_entitlements:
        result = subprocess.run(
            ["codesign", "-d", "--entitlements", "-", str(target)],
            capture_output=True, text=True,
        )
        output = result.stdout + result.stderr
        for ent in ("com.apple.security.virtualization", "com.apple.security.hypervisor"):
            if ent not in output:
                print(f"error: {target} missing entitlement {ent}", file=sys.stderr)
                return False
    return True


def bundle_daemon(
    daemon_binary: Path,
    output_dir: Path,
    *,
    provisioning_profile: Path | None = None,
    sign_identity: str | None = None,
    entitlements: Path | None = None,
    version: str = "1.0",
) -> Path:
    """
    Create the .app bundle and return its path.

    Output structure:
        <output_dir>/com.arcboxlabs.desktop.daemon.app/
        └── Contents/
            ├── Info.plist
            ├── PkgInfo
            ├── MacOS/
            │   └── com.arcboxlabs.desktop.daemon
            └── embedded.provisionprofile  (if provided)
    """
    bundle_dir = output_dir / f"{EXECUTABLE_NAME}.app"
    contents = bundle_dir / "Contents"
    macos_dir = contents / "MacOS"

    # Clean previous bundle if present.
    if bundle_dir.exists():
        shutil.rmtree(bundle_dir)

    macos_dir.mkdir(parents=True)

    # 1. Copy daemon binary.
    dest_binary = macos_dir / EXECUTABLE_NAME
    shutil.copy2(daemon_binary, dest_binary)
    dest_binary.chmod(0o755)
    print(f"  Copied daemon binary → {dest_binary}")

    # 2. Create Info.plist + PkgInfo.
    create_info_plist(contents, version)
    create_pkginfo(contents)
    print(f"  Created Info.plist (version={version})")

    # 3. Embed provisioning profile.
    if provisioning_profile:
        profile_dest = contents / "embedded.provisionprofile"
        shutil.copy2(provisioning_profile, profile_dest)
        print(f"  Embedded provisioning profile → {profile_dest}")

    # 4. Sign the bundle.
    if sign_identity:
        codesign(bundle_dir, sign_identity, entitlements)
        if not verify_signature(bundle_dir, check_entitlements=bool(entitlements)):
            print("error: daemon bundle signature verification failed", file=sys.stderr)
            sys.exit(1)
        print(f"  Signed daemon bundle with identity: {sign_identity}")
    else:
        # Ad-hoc sign for local dev.
        subprocess.run(
            ["codesign", "--force", "--deep", "-s", "-", str(bundle_dir)],
            check=True,
        )
        print("  Ad-hoc signed daemon bundle")

    return bundle_dir


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Bundle arcbox-daemon into a minimal .app for AMFI profile support.",
    )
    parser.add_argument(
        "daemon_binary",
        type=Path,
        help="Path to the arcbox-daemon Mach-O binary",
    )
    parser.add_argument(
        "output_dir",
        type=Path,
        help="Directory to create the .app bundle in (e.g. Contents/Frameworks)",
    )
    parser.add_argument(
        "--provisioning-profile",
        type=Path,
        default=None,
        help="Path to .provisionprofile to embed",
    )
    parser.add_argument(
        "--sign",
        dest="sign_identity",
        default=None,
        help='Codesign identity (e.g. "Developer ID Application: ...")',
    )
    parser.add_argument(
        "--entitlements",
        type=Path,
        default=None,
        help="Path to entitlements plist for the daemon",
    )
    parser.add_argument(
        "--version",
        default="1.0",
        help="CFBundleVersion / CFBundleShortVersionString (default: 1.0)",
    )

    args = parser.parse_args()

    # Validate inputs.
    if not args.daemon_binary.is_file():
        print(f"error: daemon binary not found: {args.daemon_binary}", file=sys.stderr)
        sys.exit(1)
    if args.provisioning_profile and not args.provisioning_profile.is_file():
        print(f"error: provisioning profile not found: {args.provisioning_profile}", file=sys.stderr)
        sys.exit(1)
    if args.entitlements and not args.entitlements.is_file():
        print(f"error: entitlements not found: {args.entitlements}", file=sys.stderr)
        sys.exit(1)

    args.output_dir.mkdir(parents=True, exist_ok=True)

    bundle_path = bundle_daemon(
        args.daemon_binary,
        args.output_dir,
        provisioning_profile=args.provisioning_profile,
        sign_identity=args.sign_identity,
        entitlements=args.entitlements,
        version=args.version,
    )
    print(f"  Bundle: {bundle_path}")


if __name__ == "__main__":
    main()
