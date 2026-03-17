<div align="center">

# ArcBox Desktop

**Native macOS GUI for ArcBox — containers, VMs, and sandboxes at your fingertips.**

[![macOS](https://img.shields.io/badge/macOS-15%2B-000?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Release](https://img.shields.io/github/v/release/arcboxlabs/arcbox-desktop?color=green)](https://github.com/arcboxlabs/arcbox-desktop/releases)

</div>

---

## Overview

ArcBox Desktop is the official graphical interface for the [ArcBox](https://github.com/arcboxlabs/arcbox) runtime. It communicates with `arcbox-daemon` over gRPC and the Docker Engine API, providing a three-column interface for managing your entire ArcBox environment.

```
┌─────────────────────┐
│  ArcBox Desktop     │  SwiftUI
└──────────┬──────────┘
           │ gRPC + Docker API (Unix socket)
           ▼
┌─────────────────────┐
│  arcbox-daemon      │  Rust
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Linux Guest VM     │
│  arcbox-agent       │
└─────────────────────┘
```

## Features

- **Docker** — containers, images, volumes, networks; logs, terminal, file browser
- **Kubernetes** — pods and services
- **Machines** — full Linux VM lifecycle, SSH, terminal
- **Sandboxes** — create from templates, manage lifecycle
- **Real-time sync** — Docker event stream with debounced UI updates
- **Privileged helper** — XPC daemon for Docker socket symlink, CLI install, DNS config
- **Auto-updates** — Sparkle framework for OTA distribution

## Requirements

- macOS 15 (Sequoia) or later
- Apple Silicon (M1+)
- Xcode 16+ (for building)

## Development Setup

```bash
# Clone
git clone https://github.com/arcboxlabs/arcbox-desktop.git
cd arcbox-desktop

# Configure local build settings
cp Local.xcconfig.example Local.xcconfig
# Edit Local.xcconfig: set DEVELOPMENT_TEAM and SENTRY_DSN

# Open in Xcode
open ArcBox.xcodeproj
```

The build automatically fetches `arcbox-daemon` and `arcbox-agent` binaries from your local [arcbox](https://github.com/arcboxlabs/arcbox) build or cache. To build them from source:

```bash
cd ../arcbox
cargo build --release -p arcbox-daemon
cargo build --release -p arcbox-agent --target aarch64-unknown-linux-musl
```

## Project Structure

```
ArcBox/                    SwiftUI app
├── Views/                 60 view files (Containers, Images, Machines, ...)
├── ViewModels/            MVVM state management
├── Models/                Data models
├── Services/              DockerEventMonitor
├── Components/            Reusable UI components
└── Theme/                 Design tokens

ArcBoxHelper/              Privileged XPC helper (runs as root)

Packages/
├── ArcBoxClient/          gRPC client library (protobuf generated stubs)
└── DockerClient/          Docker Engine API client (OpenAPI generated)

LaunchDaemons/             launchd plist for daemon and helper
scripts/                   Build, packaging, and distribution scripts
```

## Tech Stack

| Layer | Technology |
|-------|------------|
| UI | SwiftUI + `@Observable` |
| Daemon communication | gRPC (grpc-swift + protobuf) |
| Docker API | OpenAPI-generated client |
| Privileged operations | NSXPCConnection |
| Daemon management | SMAppService |
| Crash reporting | Sentry |
| Auto-updates | Sparkle |

## License

Proprietary. All rights reserved.
