#!/usr/bin/env python3
"""
Embed arcbox binaries into the Xcode app bundle.

This build phase script:
  1. Builds Rust binaries via `make build-rust` in the arcbox repo (incremental)
  2. Copies binaries into the app bundle (incremental, skips unchanged)
  3. Signs CLI/helper with Xcode's identity, daemon with Developer ID

The daemon requires Developer ID signing for virtualization/hypervisor
entitlements, even in Debug builds. Using Xcode's Development certificate
causes launchd to silently refuse to exec the daemon.

Set SKIP_RUST_BUILD=1 to skip entirely (used by CI for Swift-only checks).
"""
from __future__ import annotations

import filecmp
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

DAEMON_NAME = "com.arcboxlabs.desktop.daemon"


# ── Helpers ──────────────────────────────────────────────


def note(msg: str) -> None:
    print(f"note: {msg}")


def warn(msg: str) -> None:
    print(f"warning: {msg}")


def error(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)


def env(key: str, default: str = "") -> str:
    return os.environ.get(key, default)


def is_macho(path: Path) -> bool:
    """Check if a file is a valid Mach-O binary."""
    if not path.is_file():
        return False
    with open(path, "rb") as f:
        magic = f.read(4).hex()
    return magic in ("cffaedfe", "cafebabe", "feedfacf", "cefaedfe")


def sync_binary(src: Path, dst: Path) -> bool:
    """Copy src to dst only if content differs. Returns True if copied."""
    if dst.is_file() and filecmp.cmp(src, dst, shallow=False):
        return False
    shutil.copy2(src, dst)
    return True


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, **kwargs)


def codesign_verify(binary: Path) -> bool:
    """Verify a binary's code signature."""
    result = run(["codesign", "--verify", "--strict", str(binary)],
                 capture_output=True)
    if result.returncode != 0:
        warn(f"{binary} has invalid or missing code signature")
        return False
    return True


def codesign_check_entitlements(binary: Path, required: list[str]) -> bool:
    """Check that a binary has all required entitlements."""
    result = run(
        ["codesign", "-d", "--entitlements", "-", str(binary)],
        capture_output=True, text=True,
    )
    output = result.stdout + result.stderr
    missing = [ent for ent in required if ent not in output]
    if missing:
        for ent in missing:
            error(f"{binary} is missing {ent} entitlement")
        return False
    return True


def codesign_sign(
    target: Path,
    identity: str,
    identifier: str | None = None,
    entitlements: Path | None = None,
    timestamp: bool = True,
) -> None:
    """Sign a binary or bundle with hardened runtime."""
    cmd = ["codesign", "--force", "--options", "runtime"]
    if timestamp:
        cmd += ["--timestamp"]
    cmd += ["--sign", identity]
    if identifier:
        cmd += ["--identifier", identifier]
    if entitlements:
        cmd += ["--entitlements", str(entitlements)]
    cmd.append(str(target))
    run(cmd, check=True)


def codesign_adhoc(target: Path) -> None:
    run(["codesign", "--force", "-s", "-", str(target)], check=True)


def sign_with_xcode_identity(target: Path, identifier: str) -> None:
    """Sign a binary with Xcode's build identity (for non-daemon binaries)."""
    expanded = env("EXPANDED_CODE_SIGN_IDENTITY")
    code_sign = env("CODE_SIGN_IDENTITY")

    if expanded and expanded != "-":
        codesign_sign(target, expanded, identifier=identifier, timestamp=True)
    elif code_sign and code_sign != "-":
        codesign_sign(target, code_sign, identifier=identifier, timestamp=False)
    else:
        codesign_adhoc(target)


# ── Developer ID Detection ───────────────────────────────


def find_developer_id(preferred_org: str | None = None) -> str | None:
    """
    Find a Developer ID signing identity from the keychain.

    Returns the SHA-1 hash (not the name) to avoid ambiguity when
    duplicate certificates exist. If preferred_org is set, tries to
    match that organization first.
    """
    override = env("DAEMON_SIGN_IDENTITY")
    if override:
        return override

    result = run(
        ["security", "find-identity", "-v", "-p", "codesigning"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        return None

    # Parse lines like:
    #   8) 34B370D0... "Developer ID Application: ArcBox, Inc. (422ACSY6Y5)"
    pattern = re.compile(
        r'^\s*\d+\)\s+([A-F0-9]{40})\s+"(Developer ID Application: [^"]+)"',
    )
    candidates: list[tuple[str, str]] = []  # (sha1, name)
    for line in result.stdout.splitlines():
        m = pattern.match(line)
        if m:
            candidates.append((m.group(1), m.group(2)))

    if not candidates:
        return None

    # Prefer the org-specific certificate if available.
    if preferred_org:
        for sha1, name in candidates:
            if preferred_org in name:
                return sha1

    # Fall back to the first Developer ID found.
    return candidates[0][0]


# ── Resolve arcbox repo ──────────────────────────────────


def find_arcbox_repo(project_dir: Path) -> Path | None:
    override = env("ARCBOX_DIR")
    if override:
        return Path(override)
    for candidate in [project_dir / "arcbox", project_dir.parent / "arcbox"]:
        if (candidate / "Cargo.toml").is_file():
            return candidate
    return None


# ── Main ─────────────────────────────────────────────────


def main() -> None:
    if env("SKIP_RUST_BUILD") == "1":
        note("SKIP_RUST_BUILD=1, skipping binary embedding")
        return

    # Xcode strips PATH; ensure cargo and homebrew tools are reachable.
    home = Path.home()
    os.environ["PATH"] = (
        f"{home}/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:"
        + os.environ.get("PATH", "")
    )

    project_dir = Path(env("PROJECT_DIR", ".")).resolve()
    built_products = Path(env("BUILT_PRODUCTS_DIR"))
    contents_folder = env("CONTENTS_FOLDER_PATH")
    script_dir = project_dir / "scripts"

    version = (project_dir / "arcbox.version").read_text().strip()
    cache_dir = project_dir / ".build" / "arcbox-binaries" / version

    arcbox_repo = find_arcbox_repo(project_dir)
    local_dir = Path(arcbox_repo, "target", "release") if arcbox_repo else None
    local_agent_dir = (
        Path(arcbox_repo, "target", "aarch64-unknown-linux-musl", "release")
        if arcbox_repo else None
    )

    # ── Build ────────────────────────────────────────────
    if arcbox_repo and (arcbox_repo / "Makefile").is_file():
        note("Building arcbox binaries (incremental)...")
        run(
            ["make", "-C", str(project_dir), "build-rust",
             f"ARCBOX_DIR={arcbox_repo}"],
            check=True,
        )

    # ── Resolve source ───────────────────────────────────
    src_dir: Path | None = None
    agent_src: Path | None = None

    if (local_dir
            and (local_dir / "abctl").is_file()
            and (local_dir / "arcbox-daemon").is_file()):
        if not is_macho(local_dir / "arcbox-daemon"):
            error(f"{local_dir}/arcbox-daemon is not a valid Mach-O binary")
            sys.exit(1)
        note(f"Using local arcbox binaries from {local_dir}")
        src_dir = local_dir
        agent_src = local_agent_dir / "arcbox-agent" if local_agent_dir else None
    elif (cache_dir / "abctl").is_file() and (cache_dir / "arcbox-daemon").is_file():
        if not is_macho(cache_dir / "arcbox-daemon"):
            error("Cached arcbox-daemon is not a valid Mach-O binary.")
            error(f"  Remove the stale cache and rebuild: rm -rf {cache_dir}")
            sys.exit(1)
        note(f"Using cached arcbox {version} binaries")
        src_dir = cache_dir
        agent_src = cache_dir / "arcbox-agent"
    else:
        error(f"arcbox {version} binaries not found.")
        print()
        print("Option 1: Build from source")
        print(f"  cd {project_dir.parent / 'arcbox'} && cargo build --release")
        print()
        print("Option 2: Download from GitHub Releases")
        print(f"  Download {version} from https://github.com/arcboxlabs/arcbox/releases/tag/{version}")
        print(f"  Extract and place abctl, arcbox-daemon, arcbox-agent into:")
        print(f"    {cache_dir}/")
        sys.exit(1)

    # ── Embed daemon → Contents/Frameworks/*.app ─────────
    #
    # The daemon MUST be signed with a Developer ID certificate.
    # Restricted entitlements require Developer ID for AMFI to accept them.
    frameworks_dir = built_products / contents_folder / "Frameworks"
    daemon_bundle = frameworks_dir / f"{DAEMON_NAME}.app"
    daemon_binary = daemon_bundle / "Contents" / "MacOS" / DAEMON_NAME

    # Find Developer ID (prefer ArcBox, Inc. cert, use SHA-1 hash to avoid ambiguity).
    daemon_identity = find_developer_id(preferred_org="ArcBox, Inc.")
    if not daemon_identity:
        warn("No Developer ID signing identity found for daemon.")
        warn("  Daemon will use ad-hoc signing — restricted entitlements will NOT work.")
        warn("  Install a Developer ID certificate or set DAEMON_SIGN_IDENTITY.")

    # Rebuild bundle if the source binary changed.
    if not daemon_binary.is_file() or not filecmp.cmp(
        src_dir / "arcbox-daemon", daemon_binary, shallow=False
    ):
        note("Building daemon .app bundle...")
        bundle_args = [
            str(src_dir / "arcbox-daemon"),
            str(frameworks_dir),
            "--version", version,
        ]
        if daemon_identity:
            ent_path = arcbox_repo / "bundle" / "arcbox.entitlements" if arcbox_repo else None
            if ent_path and ent_path.is_file():
                bundle_args += ["--sign", daemon_identity, "--entitlements", str(ent_path)]
            else:
                if ent_path:
                    warn(f"Entitlements file not found at {ent_path}")
                bundle_args += ["--sign", daemon_identity]

        run(
            ["/usr/bin/python3", str(script_dir / "bundle-daemon.py")] + bundle_args,
            check=True,
        )
        note(f"Daemon bundle created at {daemon_bundle}")
    else:
        note("Daemon bundle unchanged, skipping rebuild")

    # Verify daemon signature and entitlements.
    required_ents = [
        "com.apple.security.virtualization",
        "com.apple.security.hypervisor",
    ]
    if daemon_identity:
        if not codesign_verify(daemon_binary):
            error(f"Daemon at {daemon_binary} has invalid signature.")
            error(f"  Identity used: {daemon_identity}")
            sys.exit(1)
        if not codesign_check_entitlements(daemon_binary, required_ents):
            error(f"Daemon at {daemon_binary} must be signed with Developer ID + entitlements.")
            error(f"  Identity used: {daemon_identity}")
            sys.exit(1)
    else:
        codesign_verify(daemon_binary)

    # Clean up legacy Helpers/ location if present.
    legacy_daemon = built_products / contents_folder / "Helpers" / DAEMON_NAME
    if legacy_daemon.is_file():
        legacy_daemon.unlink()
        note(f"Removed legacy daemon at Helpers/{DAEMON_NAME}")

    # ── Embed abctl → Contents/MacOS/bin/ ────────────────
    cli_dir = built_products / contents_folder / "MacOS" / "bin"
    cli_dir.mkdir(parents=True, exist_ok=True)

    abctl_dst = cli_dir / "abctl"
    if sync_binary(src_dir / "abctl", abctl_dst):
        sign_with_xcode_identity(abctl_dst, "com.arcboxlabs.desktop.abctl")
        note("Embedded and signed abctl → MacOS/bin/abctl")
    else:
        if not codesign_verify(abctl_dst):
            warn("abctl signature invalid, consider cleaning build")
        note("abctl unchanged, skipping copy")

    # ── Embed arcbox-helper → Contents/MacOS/bin/ ────────
    helper_src = src_dir / "arcbox-helper"
    if helper_src.is_file():
        helper_dst = cli_dir / "arcbox-helper"
        if sync_binary(helper_src, helper_dst):
            sign_with_xcode_identity(helper_dst, "com.arcboxlabs.desktop.helper")
            note("Embedded and signed arcbox-helper → MacOS/bin/arcbox-helper")
        else:
            if not codesign_verify(helper_dst):
                warn("arcbox-helper signature invalid, consider cleaning build")
            note("arcbox-helper unchanged, skipping copy")
    else:
        warn(f"arcbox-helper not found at {helper_src}, skipping")

    # ── Embed arcbox-agent → Contents/Resources/bin/ ─────
    # Linux musl binary — no macOS signing needed.
    if agent_src and agent_src.is_file():
        agent_dir = built_products / contents_folder / "Resources" / "bin"
        agent_dir.mkdir(parents=True, exist_ok=True)
        if sync_binary(agent_src, agent_dir / "arcbox-agent"):
            note("Embedded arcbox-agent → Resources/bin/arcbox-agent")
        else:
            note("arcbox-agent unchanged, skipping copy")
    else:
        warn(f"arcbox-agent not found at {agent_src}, skipping")


if __name__ == "__main__":
    main()
