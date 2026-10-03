# Contributing to ArcBox Desktop

Bug reports, feature requests, and code are all welcome. This repo is the macOS
app; the runtime lives in [arcboxlabs/arcbox](https://github.com/arcboxlabs/arcbox).

**Which repo?** If the app shows it wrong, file here. If containers, VMs,
networking, or `abctl` behave wrong — including when you hit it through the app —
file against the runtime. When in doubt, file here and we will move it.

## Getting set up

[docs/development.md](docs/development.md) covers the build: `Local.xcconfig`, the
Makefile targets, why `xcodebuild` must not be called directly, and how to get a
bundle with a real daemon in it.

[AGENTS.md](AGENTS.md) is the shorter companion — code style, and the SwiftUI
startup pitfalls this app keeps running into.

## Before you open a PR

```bash
make lint      # swift-format --strict + swiftlint, exactly what CI runs
make test
```

- Added or removed a file? Run `make generate-xcodeproj` and commit the result.
  CI fails on an out-of-date `ArcBox.xcodeproj`.
- Touched `xtask/`? Run `make lint-xtask test-xtask`.
- Changed the embedded daemon? Use `make bump-arcbox VERSION=vX.Y.Z` so
  `arcbox.version` and the generated gRPC client move together.

## Code standards

- Swift 6 strict concurrency, `MainActor` by default. An isolation violation is a
  warning at build time and a crash at runtime — do not ship past one.
- `@Observable` view models; environment injection through custom `EnvironmentKey`.
- `async/await` over Combine. No Combine, and no third-party UI frameworks.
- Log through the `Log` enum (`ClientLog` inside `Packages/`), not `print`.
- Comments in English, and only where the code is not self-evident.
- Any lint or type-check suppression carries a reason on the same line.

## Commits and PRs

- Conventional commits: `type(scope): summary`, e.g.
  `fix(containers): keep the log stream alive across a daemon restart`.
  release-please parses them to cut releases, so the type decides what users see
  in the changelog.
- Keep commits atomic and buildable.
- No `Co-Authored-By` lines.
- `CHANGELOG.md` and `Version.xcconfig` are generated. Do not edit them outside
  the release-please PR. Before merging that PR, add a `### Highlights` section
  under the new release with concise user-facing changes and impact. Sparkle
  shows it in the update dialog, above the release's Features and Bug Fixes.
  Without it the update dialog falls back to those lists alone, so write it
  whenever the build deserves better than a list of commit subjects — and the
  release PR fails outright when there is neither.
- Merging the release PR cuts the tag and opens a draft GitHub release. The
  Release DMG workflow attaches the signed DMG and publishes it, so a release
  that stays a draft means that build failed.

## Reporting security issues

Do not open a public issue — see [SECURITY.md](SECURITY.md).

## License

By contributing you agree that your work is licensed under
[MIT](LICENSE-MIT) OR [Apache-2.0](LICENSE-APACHE).
