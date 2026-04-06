#!/usr/bin/env python3
"""
Build ArcBox.app and package it into a signed/notarized DMG.

Usage:
    scripts/package-dmg.py [--sign <identity>] [--notarize] [--provisioning-profile <path>]

Environment variables:
    DESKTOP_REPO   - Path to arcbox-desktop checkout (default: script dir/..)
    ARCBOX_DIR     - Path to arcbox checkout (default: DESKTOP_REPO/../arcbox or ./arcbox)
    PSTRAMP_DIR    - Path to pstramp checkout (default: ARCBOX_DIR/../pstramp)
    VERSION        - Release version (default: read from Version.xcconfig)
    SPARKLE_FEED_URL - Sparkle auto-update feed URL to inject into Info.plist

App bundle layout:

    Contents/
    ├── MacOS/
    │   ├── ArcBox                   # Main GUI app
    │   ├── pstramp                 # Process spawn trampoline
    │   ├── bin/
    │   │   └── abctl               # CLI binary
    │   └── xbin/
    │       ├── docker              # Docker CLI tools
    │       ├── docker-buildx
    │       ├── docker-compose
    │       └── docker-credential-osxkeychain
    ├── Frameworks/
    │   └── com.arcboxlabs.desktop.daemon.app/
    ├── Resources/
    │   ├── assets.lock
    │   ├── assets/{version}/       # Boot assets (kernel, rootfs, manifest)
    │   ├── bin/
    │   │   └── arcbox-agent        # Guest agent (Linux musl binary)
    │   ├── runtime/                # Runtime binaries
    │   └── completions/{bash,zsh,fish}/
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

BUNDLE_ID = "com.arcboxlabs.desktop"
APP_NAME = "ArcBox"
DAEMON_NAME = "com.arcboxlabs.desktop.daemon"
DOCKER_TOOLS = ["docker", "docker-buildx", "docker-compose", "docker-credential-osxkeychain"]


# ── Helpers ──────────────────────────────────────────────────────────────────


def run(cmd: list[str], *, check: bool = True, **kwargs) -> subprocess.CompletedProcess:
    """Run a command, printing it on failure."""
    return subprocess.run(cmd, check=check, **kwargs)


def sign_binary(target: Path, identity: str, *extra_args: str) -> None:
    """Sign a binary with hardened runtime. No-op when identity is empty."""
    if not identity:
        return
    cmd = ["codesign", "--force", "--options", "runtime",
           "--sign", identity, "--timestamp"]
    cmd.extend(extra_args)
    cmd.append(str(target))
    run(cmd)


def fatal(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def warn(msg: str) -> None:
    print(f"  Warning: {msg}")


def resolve_arcbox_dir(desktop_repo: Path) -> Path:
    """Locate the arcbox checkout. Respects ARCBOX_DIR env var."""
    env_dir = os.environ.get("ARCBOX_DIR")
    if env_dir:
        return Path(env_dir).resolve()
    for candidate in [desktop_repo / "arcbox", desktop_repo.parent / "arcbox"]:
        if candidate.is_dir():
            return candidate.resolve()
    fatal("cannot locate arcbox checkout")
    raise SystemExit(1)  # unreachable, keeps type checker happy


def read_version(desktop_repo: Path) -> str:
    """Read version from VERSION env var or Version.xcconfig."""
    version = os.environ.get("VERSION", "")
    if not version:
        xcconfig = desktop_repo / "Version.xcconfig"
        if xcconfig.exists():
            m = re.search(r"^MARKETING_VERSION\s*=\s*(.+?)(?:\s*//.*)?$",
                          xcconfig.read_text(), re.MULTILINE)
            version = m.group(1).strip() if m else ""
        version = version or "0.0.0"
    return version.lstrip("v")


def read_boot_version(lock_file: Path) -> str:
    """Parse boot version from assets.lock (TOML-like)."""
    if not lock_file.exists():
        fatal(f"{lock_file} not found")
    in_boot = False
    for line in lock_file.read_text().splitlines():
        if line.strip() == "[boot]":
            in_boot = True
            continue
        if in_boot and line.startswith("version"):
            m = re.search(r'"(.+?)"', line)
            if m:
                return m.group(1)
    fatal(f"cannot parse boot version from {lock_file}")
    raise SystemExit(1)


def git_commit_count(repo: Path) -> str:
    result = run(["git", "-C", str(repo), "rev-list", "--count", "HEAD"],
                 capture_output=True, text=True)
    return result.stdout.strip()


# ── Build steps ──────────────────────────────────────────────────────────────


def build_swift_app(
    desktop_repo: Path,
    arcbox_dir: Path,
    build_number: str,
    sign_identity: str,
) -> Path:
    """Build the Swift app via xcodebuild and return the .app path."""
    print("--- Building Swift app ---")

    derived_data = desktop_repo / ".build" / "DerivedData"
    spm_clones = Path("/tmp/arcbox-spm-packages")

    flags = [
        "xcodebuild", "build",
        "-project", str(desktop_repo / "ArcBox.xcodeproj"),
        "-scheme", "ArcBox",
        "-configuration", "Release",
        "-derivedDataPath", str(derived_data),
        "-clonedSourcePackagesDirPath", str(spm_clones),
        "-skipPackagePluginValidation",
        f"ARCBOX_DIR={arcbox_dir}",
        f"CURRENT_PROJECT_VERSION={build_number}",
    ]
    if sign_identity:
        flags += [f"CODE_SIGN_IDENTITY={sign_identity}", "CODE_SIGN_STYLE=Manual"]

    # Pipe through tail to reduce noise.
    proc = subprocess.Popen(flags, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert proc.stdout is not None
    lines: list[str] = []
    for raw in proc.stdout:
        line = raw.decode("utf-8", errors="replace")
        lines.append(line)
    proc.wait()
    # Print last 20 lines.
    for line in lines[-20:]:
        print(line, end="")
    if proc.returncode != 0:
        fatal("xcodebuild failed")

    products = derived_data / "Build" / "Products" / "Release"
    apps = list(products.glob("*.app"))
    if not apps:
        fatal(".app bundle not found after build")
    return apps[0]


def inject_sparkle_feed_url(app_bundle: Path) -> None:
    """Inject Sparkle feed URL into Info.plist if SPARKLE_FEED_URL is set."""
    url = os.environ.get("SPARKLE_FEED_URL", "")
    if not url:
        return
    plist = app_bundle / "Contents" / "Info.plist"
    run(["plutil", "-replace", "SUFeedURL", "-string", url, str(plist)])
    print(f"  SUFeedURL: {url}")


def embed_boot_assets(app_bundle: Path, arcbox_dir: Path) -> None:
    """Embed boot-assets into Contents/Resources/assets/{version}/."""
    print("--- Embedding boot-assets ---")

    lock_file = arcbox_dir / "assets.lock"
    boot_version = read_boot_version(lock_file)
    print(f"  Boot-asset version: {boot_version}")

    # Locate cached boot-assets.
    boot_cache: Path | None = None
    for candidate in [
        arcbox_dir / "target" / "boot-assets" / boot_version,
        Path.home() / ".arcbox" / "boot" / boot_version,
    ]:
        if (candidate / "manifest.json").is_file():
            boot_cache = candidate
            break

    if boot_cache is None:
        fatal(f"boot-assets v{boot_version} not found.\n  Run 'abctl boot prefetch' first.")

    # Copy assets.lock → Contents/Resources/
    resources = app_bundle / "Contents" / "Resources"
    shutil.copy2(lock_file, resources / "assets.lock")

    # Copy boot files.
    boot_dest = resources / "assets" / boot_version
    boot_dest.mkdir(parents=True, exist_ok=True)
    for name in ["kernel", "rootfs.erofs", "manifest.json"]:
        shutil.copy2(boot_cache / name, boot_dest / name)
    print(f"  Embedded boot-assets from {boot_cache} → {boot_dest}")


def embed_abctl(app_bundle: Path, arcbox_dir: Path, sign_identity: str) -> None:
    """Embed abctl CLI → Contents/MacOS/bin/abctl."""
    cli_bin = arcbox_dir / "target" / "release" / "abctl"
    if not cli_bin.is_file():
        return
    print("--- Embedding abctl CLI ---")
    bin_dir = app_bundle / "Contents" / "MacOS" / "bin"
    bin_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(cli_bin, bin_dir / "abctl")
    sign_binary(bin_dir / "abctl", sign_identity)
    print("  Copied abctl → MacOS/bin/abctl")


def embed_agent(app_bundle: Path, arcbox_dir: Path) -> None:
    """Embed arcbox-agent → Contents/Resources/bin/arcbox-agent."""
    agent_bin = arcbox_dir / "target" / "aarch64-unknown-linux-musl" / "release" / "arcbox-agent"
    if agent_bin.is_file():
        print("--- Embedding arcbox-agent ---")
        agent_dir = app_bundle / "Contents" / "Resources" / "bin"
        agent_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(agent_bin, agent_dir / "arcbox-agent")
        print("  Copied arcbox-agent → Resources/bin/arcbox-agent")
    else:
        warn(f"arcbox-agent not found at {agent_bin}")
        print("  Build with: cargo build -p arcbox-agent --target aarch64-unknown-linux-musl --release")


def embed_docker_tools(app_bundle: Path, sign_identity: str) -> None:
    """Embed Docker CLI tools → Contents/MacOS/xbin/."""
    print("--- Embedding Docker CLI tools ---")

    src_dir = Path.home() / ".arcbox" / "runtime" / "bin"
    dest_dir = app_bundle / "Contents" / "MacOS" / "xbin"
    dest_dir.mkdir(parents=True, exist_ok=True)
    count = 0

    for tool in DOCKER_TOOLS:
        src = src_dir / tool
        if src.is_file():
            shutil.copy2(src, dest_dir / tool)
            sign_binary(dest_dir / tool, sign_identity)
            print(f"  Embedded {tool} → MacOS/xbin/{tool}")
            count += 1

    if count == 0:
        warn(f"no Docker tools found at {src_dir}")
        print("  Run 'abctl docker setup' to download them first.")
        try:
            dest_dir.rmdir()
        except OSError:
            pass


def embed_runtime(app_bundle: Path, arcbox_dir: Path, sign_identity: str) -> None:
    """Embed runtime binaries → Contents/Resources/runtime/."""
    print("--- Preparing and embedding runtime binaries ---")

    # Run abctl boot prefetch to ensure all runtime binaries are cached.
    cli_bin = arcbox_dir / "target" / "release" / "abctl"
    if cli_bin.is_file():
        print("  Running abctl boot prefetch...")
        result = run([str(cli_bin), "boot", "prefetch"], check=False)
        if result.returncode != 0:
            fatal("abctl boot prefetch failed")
    else:
        warn(f"abctl not found at {cli_bin}, skipping prefetch")

    runtime_src = Path.home() / ".arcbox" / "runtime"
    runtime_dest = app_bundle / "Contents" / "Resources" / "runtime"
    count = 0

    if runtime_src.is_dir():
        for src_file in runtime_src.rglob("*"):
            if not src_file.is_file():
                continue
            # Only copy executable files (skip .sha256, .tmp, etc.)
            if not os.access(src_file, os.X_OK):
                continue
            rel = src_file.relative_to(runtime_src)
            dest_file = runtime_dest / rel
            dest_file.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src_file, dest_file)
            sign_binary(dest_file, sign_identity)
            print(f"  Embedded {rel}")
            count += 1

    if count == 0:
        warn(f"no runtime binaries found at {runtime_src}")
        print("  Run 'abctl boot prefetch' to download them first.")
        shutil.rmtree(runtime_dest, ignore_errors=True)


def embed_completions(app_bundle: Path) -> None:
    """Generate Docker shell completions from the embedded Docker CLI
    and place them into Contents/Resources/completions/.

    Completions are generated at build time so the app bundle is
    self-contained and does not depend on the build machine having
    pre-populated ~/.arcbox/completions/.
    """
    print("--- Generating and embedding Docker completions ---")

    docker_bin = app_bundle / "Contents" / "MacOS" / "xbin" / "docker"
    comp_dest = app_bundle / "Contents" / "Resources" / "completions"

    # Map shell name → (completion subcommand arg, output filename).
    shell_map: dict[str, str] = {
        "bash": "docker",
        "zsh": "_docker",
        "fish": "docker.fish",
    }

    for shell, filename in shell_map.items():
        dest_dir = comp_dest / shell
        dest_dir.mkdir(parents=True, exist_ok=True)
        if docker_bin.is_file():
            result = subprocess.run(
                [str(docker_bin), "completion", shell],
                capture_output=True, text=True,
            )
            if result.returncode == 0 and result.stdout.strip():
                (dest_dir / filename).write_text(result.stdout)
                print(f"  Generated {shell} completion → {filename}")
            else:
                warn(f"docker completion {shell} failed: {result.stderr.strip()}")
        else:
            warn("docker binary not found in app bundle, cannot generate completions")


def embed_pstramp(app_bundle: Path, arcbox_dir: Path, sign_identity: str) -> None:
    """Embed pstramp → Contents/MacOS/pstramp."""
    print("--- Embedding pstramp ---")

    pstramp_dir = os.environ.get("PSTRAMP_DIR", "")
    candidates = []
    if pstramp_dir:
        candidates.append(Path(pstramp_dir) / "target" / "release" / "pstramp")
    candidates.append(arcbox_dir.parent / "pstramp" / "target" / "release" / "pstramp")

    pstramp_src: Path | None = None
    for c in candidates:
        if c.is_file():
            pstramp_src = c
            break

    if pstramp_src:
        dest = app_bundle / "Contents" / "MacOS" / "pstramp"
        shutil.copy2(pstramp_src, dest)
        sign_binary(dest, sign_identity)
        print(f"  Embedded pstramp from {pstramp_src}")
    else:
        warn("pstramp not found. Build it with: cargo build --release -p pstramp")


def bundle_daemon(
    app_bundle: Path,
    arcbox_dir: Path,
    desktop_repo: Path,
    version: str,
    sign_identity: str,
    provisioning_profile: str,
) -> None:
    """Bundle daemon into .app with provisioning profile."""
    print("--- Bundling daemon ---")

    daemon_name = DAEMON_NAME
    frameworks = app_bundle / "Contents" / "Frameworks"
    already_bundled = frameworks / f"{daemon_name}.app" / "Contents" / "MacOS" / daemon_name
    daemon_tmp: Path | None = None

    # Locate daemon binary from multiple possible locations.
    if already_bundled.is_file():
        # Xcode already created the bundle. Extract binary before rebuild.
        tmp_fd, tmp_path = tempfile.mkstemp()
        os.close(tmp_fd)
        daemon_tmp = Path(tmp_path)
        shutil.copy2(already_bundled, daemon_tmp)
        daemon_src = daemon_tmp
    elif (app_bundle / "Contents" / "Helpers" / daemon_name).is_file():
        daemon_src = app_bundle / "Contents" / "Helpers" / daemon_name
    elif (arcbox_dir / "target" / "release" / "arcbox-daemon").is_file():
        daemon_src = arcbox_dir / "target" / "release" / "arcbox-daemon"
    else:
        fatal("cannot locate arcbox-daemon binary")
        return  # unreachable

    # Call bundle-daemon.py
    bundle_args = [
        sys.executable, str(desktop_repo / "scripts" / "bundle-daemon.py"),
        str(daemon_src), str(frameworks),
        "--version", version,
    ]
    if provisioning_profile:
        if not Path(provisioning_profile).is_file():
            fatal(f"provisioning profile not found at {provisioning_profile}")
        bundle_args += ["--provisioning-profile", provisioning_profile]
    if sign_identity:
        bundle_args += [
            "--sign", sign_identity,
            "--entitlements", str(arcbox_dir / "bundle" / "arcbox.entitlements"),
        ]
    run(bundle_args)

    # Clean up temp file.
    if daemon_tmp:
        daemon_tmp.unlink(missing_ok=True)

    # Remove legacy bare binary if Xcode put it in Helpers/.
    legacy = app_bundle / "Contents" / "Helpers" / daemon_name
    legacy.unlink(missing_ok=True)
    try:
        (app_bundle / "Contents" / "Helpers").rmdir()
    except OSError:
        pass


def sign_app_bundle(
    app_bundle: Path,
    desktop_repo: Path,
    sign_identity: str,
) -> None:
    """Re-sign the entire app bundle, preserving daemon's signature."""
    print("--- Signing app bundle ---")

    daemon_bundle = app_bundle / "Contents" / "Frameworks" / f"{DAEMON_NAME}.app"

    # Stash daemon bundle to preserve its signature + provisioning profile.
    stash_dir: Path | None = None
    if daemon_bundle.is_dir():
        stash_dir = Path(tempfile.mkdtemp())
        shutil.move(str(daemon_bundle), str(stash_dir / daemon_bundle.name))
        print("  Stashed daemon bundle to preserve signature + profile")

    # Deep-sign the entire app bundle.
    run(["codesign", "--force", "--deep", "--options", "runtime",
         "--sign", sign_identity, "--timestamp", str(app_bundle)])

    # Restore pre-signed daemon bundle.
    if stash_dir:
        shutil.move(str(stash_dir / f"{DAEMON_NAME}.app"),
                     str(app_bundle / "Contents" / "Frameworks" / f"{DAEMON_NAME}.app"))
        shutil.rmtree(stash_dir, ignore_errors=True)
        print("  Restored pre-signed daemon bundle")

    # Re-sign ArcBoxHelper.
    helper_path = app_bundle / "Contents" / "Library" / "HelperTools" / "ArcBoxHelper"
    helper_entitlements = desktop_repo / "ArcBoxHelper" / "ArcBoxHelper.entitlements"
    if helper_path.is_file():
        sign_binary(helper_path, sign_identity,
                     "--identifier", "com.arcboxlabs.desktop.helper",
                     "--entitlements", str(helper_entitlements))
        print("  Signed ArcBoxHelper with hardened runtime")

    # Re-sign the outer app (nested code changed, seal must be refreshed).
    sign_binary(app_bundle, sign_identity,
                "--entitlements", str(desktop_repo / "ArcBox" / "ArcBox.entitlements"))

    run(["codesign", "--verify", "--deep", "--strict", str(app_bundle)])
    print("  Signed and verified")


def create_dmg(app_bundle: Path, dmg_path: Path) -> None:
    """Create DMG using create-dmg."""
    print("--- Creating DMG ---")

    if dmg_path.exists():
        dmg_path.unlink()

    # create-dmg exits non-zero when icon layout fails (cosmetic).
    run([
        "create-dmg",
        "--volname", APP_NAME,
        "--volicon", str(app_bundle / "Contents" / "Resources" / "AppIcon.icns"),
        "--window-pos", "200", "120",
        "--window-size", "600", "400",
        "--icon-size", "100",
        "--icon", f"{APP_NAME}.app", "150", "190",
        "--app-drop-link", "450", "190",
        "--no-internet-enable",
        str(dmg_path),
        str(app_bundle),
    ], check=False)

    if not dmg_path.is_file():
        fatal("DMG creation failed")


def sign_dmg(dmg_path: Path, sign_identity: str) -> None:
    print("--- Signing DMG ---")
    run(["codesign", "--force", "--sign", sign_identity, "--timestamp", str(dmg_path)])


def notarize_dmg(dmg_path: Path) -> None:
    """Notarize DMG via notarytool and staple."""
    print("--- Notarizing DMG ---")

    result = run(
        ["xcrun", "notarytool", "submit", str(dmg_path),
         "--keychain-profile", "arcbox-notarize",
         "--wait", "--timeout", "90m"],
        check=False, capture_output=True, text=True,
    )
    output = result.stdout + result.stderr
    print(output)

    # Extract submission ID for log retrieval.
    submission_id = ""
    for line in output.splitlines():
        line = line.strip()
        if line.startswith("id:"):
            submission_id = line.split(":", 1)[1].strip()
            break

    if "status: Accepted" in output:
        run(["xcrun", "stapler", "staple", str(dmg_path)])
        print("  Notarization complete")
    else:
        print("--- Notarization FAILED ---")
        if "status: Invalid" in output:
            print("  Status: REJECTED by Apple")
        else:
            print("  Status: did not reach 'Accepted' (timed out or unknown error)")
        if submission_id:
            print("--- Fetching notarization log ---")
            run(["xcrun", "notarytool", "log", submission_id,
                 "--keychain-profile", "arcbox-notarize"], check=False)
        sys.exit(1)


# ── Main ─────────────────────────────────────────────────────────────────────


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build ArcBox.app and package it into a signed/notarized DMG.",
    )
    parser.add_argument("--sign", dest="sign_identity", default="",
                        help="Codesign identity for signing")
    parser.add_argument("--notarize", action="store_true",
                        help="Notarize the DMG after signing")
    parser.add_argument("--provisioning-profile", default="",
                        help="Path to provisioning profile for daemon bundle")
    args = parser.parse_args()

    # Resolve paths.
    script_dir = Path(__file__).resolve().parent
    desktop_repo = Path(os.environ.get("DESKTOP_REPO", str(script_dir.parent))).resolve()
    arcbox_dir = resolve_arcbox_dir(desktop_repo)

    # Determine version and build number.
    version = read_version(desktop_repo)
    build_number = git_commit_count(desktop_repo)

    build_dir = arcbox_dir / "target" / "dmg-build"
    app_bundle = build_dir / f"{APP_NAME}.app"
    dmg_name = f"ArcBox-{version}-arm64"
    dmg_path = arcbox_dir / "target" / f"{dmg_name}.dmg"

    print("=== Building ArcBox ===")
    print(f"  Desktop repo : {desktop_repo}")
    print(f"  Arcbox dir   : {arcbox_dir}")
    print(f"  Bundle ID    : {BUNDLE_ID}")
    print(f"  Version      : {version}")
    print(f"  Build number : {build_number}")
    print(f"  Sign identity: {args.sign_identity or '(ad-hoc)'}")
    print(f"  Notarize     : {args.notarize}")

    # 1. Build Swift app.
    built_app = build_swift_app(desktop_repo, arcbox_dir, build_number, args.sign_identity)

    # Copy to staging area.
    if app_bundle.exists():
        shutil.rmtree(app_bundle)
    build_dir.mkdir(parents=True, exist_ok=True)
    shutil.copytree(built_app, app_bundle, symlinks=True)
    print(f"  App bundle: {app_bundle}")

    inject_sparkle_feed_url(app_bundle)

    # 2. Embed boot-assets.
    embed_boot_assets(app_bundle, arcbox_dir)

    # 3. Embed abctl CLI.
    embed_abctl(app_bundle, arcbox_dir, args.sign_identity)

    # 3.5. Embed arcbox-agent.
    embed_agent(app_bundle, arcbox_dir)

    # 4. Embed Docker CLI tools.
    embed_docker_tools(app_bundle, args.sign_identity)

    # 5. Embed runtime binaries.
    embed_runtime(app_bundle, arcbox_dir, args.sign_identity)

    # 6. Embed completions.
    embed_completions(app_bundle)

    # 7. Embed pstramp.
    embed_pstramp(app_bundle, arcbox_dir, args.sign_identity)

    # 8. Bundle daemon.
    bundle_daemon(app_bundle, arcbox_dir, desktop_repo, version,
                  args.sign_identity, args.provisioning_profile)

    # 9. Sign app bundle.
    if args.sign_identity:
        sign_app_bundle(app_bundle, desktop_repo, args.sign_identity)

    # 10. Create DMG.
    create_dmg(app_bundle, dmg_path)

    # 11. Sign DMG.
    if args.sign_identity:
        sign_dmg(dmg_path, args.sign_identity)

    # 12. Notarize.
    if args.notarize and args.sign_identity:
        notarize_dmg(dmg_path)

    # Done.
    size = run(["du", "-h", str(dmg_path)], capture_output=True, text=True).stdout.split()[0]
    print("=== Done ===")
    print(f"  DMG: {dmg_path}")
    print(f"  Size: {size}")


if __name__ == "__main__":
    main()
