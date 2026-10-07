<div align="center">

<img src="https://static.arcbox.dev/cdn-cgi/image/width=192,format=auto/icon/icon.png" width="96" height="96" alt="">

# ArcBox Desktop

**The native macOS app for [ArcBox](https://github.com/arcboxlabs/arcbox) — containers, Kubernetes, Linux VMs, and agent sandboxes in one window.**

[![macOS](https://img.shields.io/badge/macOS-15%2B-000?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Release](https://img.shields.io/github/v/release/arcboxlabs/arcbox-desktop?color=green)](https://github.com/arcboxlabs/arcbox-desktop/releases)
[![License](https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0-blue)](LICENSE-MIT)
[![Discord](https://img.shields.io/badge/discord-chat-5865F2?logo=discord&logoColor=white)](https://arcbox.link/discord)

![ArcBox](https://static.arcbox.dev/cdn-cgi/image/width=1920,format=auto/screenshot/2026-07-desktop/images+containers-light.png)

</div>

## Install

```bash
brew install --cask arcbox
```

Or grab the DMG from [Releases](https://github.com/arcboxlabs/arcbox-desktop/releases/latest). The app
ships the `arcbox-daemon` runtime and the `abctl` CLI, and keeps itself up to date over Sparkle — there
is nothing else to install.

**Requires** macOS 15 (Sequoia) or later on Apple Silicon.

## What it does

The runtime runs on your Mac without a Platform account or cloud control plane. Updates, image downloads, and optional anonymous telemetry use the network.

One three-column window — sources, list, detail — over everything the daemon runs:

- **Docker** — containers, images, volumes, networks. Containers group by Compose project, and each one
  opens onto info, streaming logs, an interactive terminal, and a file browser that merges the
  overlay layers exposed by the read-only `~/ArcBox/docker` export.
- **Kubernetes** — pods and services from the daemon-managed k3s cluster.
- **Machines** — full Linux VMs: create from a distro image, drive the lifecycle, and attach an
  interactive terminal.
- **Sandboxes** — disposable microVMs from templates, with ports, snapshots, and an event log.
- **Activity** — live CPU, memory, and network for the system VM and every running container.
- **Notifications** — container crash alerts distinguish unexpected exits from recent Docker stop or
  termination requests, including explicit fatal signals. Configure alerts in Settings → General.

Everything is event-driven: the Docker, machine, and sandbox event streams feed debounced updates, so the
UI reflects work started from `docker`, `abctl`, or `kubectl` without a refresh.

## Migrate an existing Docker environment

Keep Docker Desktop or OrbStack running, then choose **Help → Migrate from Docker Desktop or OrbStack…**. First-time setup also offers migration after the ArcBox runtime is ready.

Source detection reports Docker CLI failures and stops a CLI that exceeds its inspection deadline.

Review the resource counts, warnings, and required replacements before choosing **Migrate Now**. ArcBox checks the replacement targets again before starting and requires a new preview if they change. ArcBox copies supported resources without deleting them from the source. Migration can stop source containers that use the copied volumes. Keep ArcBox and the source engine open until migration completes. If both source engines are detected, select the source with `docker context use` and check again.

Quitting waits for a connected migration to finish. If the migration connection is lost while quitting, ArcBox stops reconnecting and leaves the runtime running because migration may still be copying data. Review both environments before retrying.

## Runtime storage health

Settings → Storage shows the data and metadata volumes separately. A persistent banner identifies read-only protection or unavailable storage while resource lists remain accessible. Export a diagnostic report from Storage before recovery. **Check Storage** stops workloads, preserves the runtime disks, and checks the filesystems; it leaves the runtime stopped and storage writes protected. **Recover Read-Write** also restarts and verifies writes if the checks pass. Only successful recovery releases write protection. Corruption leaves the preserved disks and diagnostics available for further recovery. Reset Docker Data removes Docker resources; it does not repair filesystems.

Storage observations require a compatible runtime. Older runtimes report unknown health. A disconnected runtime retains its last observation for diagnostics and marks the observation as stale. A read-write mount does not prove durable writes succeed.

## How it fits together

```
┌─────────────────────┐
│  ArcBox Desktop     │  SwiftUI
└──────────┬──────────┘
           │ gRPC (~/.arcbox/run/arcbox.sock)
           │ Docker Engine API (~/.arcbox/run/docker.sock)
           ▼
┌─────────────────────┐
│  arcbox-daemon      │  Rust — VMM, networking, storage
└──────────┬──────────┘
           │ vsock
           ▼
┌─────────────────────┐
│  Linux guest        │
│  arcbox-agent       │
└─────────────────────┘
```

The app is SwiftUI end to end — no Combine, no third-party UI frameworks. The daemon is a separate binary
from the [arcbox](https://github.com/arcboxlabs/arcbox) repo, pinned by [`arcbox.version`](arcbox.version)
and embedded at build time.

## Contributing

Start with [CONTRIBUTING.md](CONTRIBUTING.md); the build itself is in
[docs/development.md](docs/development.md). Bug reports and feature requests go to
[Issues](https://github.com/arcboxlabs/arcbox-desktop/issues); vulnerabilities go to
[security@arcbox.dev](SECURITY.md) instead, never to a public issue.

## License

[MIT](LICENSE-MIT) OR [Apache-2.0](LICENSE-APACHE), at your option.

The ArcBox name, mark, and screenshots are brand assets and are not covered by the source-code license —
see [BRAND.md](https://static.arcbox.dev/BRAND.md).

---

<div align="center">

[Website](https://arcbox.dev) · [Docs](https://arcbox.link/docs) · [Discord](https://arcbox.link/discord) · [Runtime](https://github.com/arcboxlabs/arcbox)

</div>
