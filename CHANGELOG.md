# Changelog

## [1.2.0](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.1.2...v1.2.0) (2026-03-12)


### Features

* add abctl CLI to build/sign pipeline and update dev team ([8b108c6](https://github.com/arcboxlabs/arcbox-desktop/commit/8b108c6c58a37271457af29b99553af1b166cc4a))


### Bug Fixes

* force SMAppService re-registration to resolve stale bundle paths ([f96f9c2](https://github.com/arcboxlabs/arcbox-desktop/commit/f96f9c2a63b11edb4d68cd8a516874c12e0e4ec2))
* make helper setup non-blocking to prevent startup hang ([f9b6023](https://github.com/arcboxlabs/arcbox-desktop/commit/f9b6023d03a98c4cf453fe69ef431386f581ce10))
* resolve ArcBoxHelper XPC daemon launch failures ([#12](https://github.com/arcboxlabs/arcbox-desktop/issues/12)) ([4623cdd](https://github.com/arcboxlabs/arcbox-desktop/commit/4623cdd9b10b8fbcba6474a4264d73964d71e6f7))

## [1.1.2](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.1.1...v1.1.2) (2026-03-11)


### Bug Fixes

* **ci:** rename arcbox checkout path to avoid case-insensitive FS collision ([8d92555](https://github.com/arcboxlabs/arcbox-desktop/commit/8d925554175b25a2ea9ddc7cf78b95084741f4f1))

## [1.1.1](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.1.0...v1.1.1) (2026-03-11)


### Bug Fixes

* **ci:** resolve SPM package name collision and shallow clone build number ([f03ea69](https://github.com/arcboxlabs/arcbox-desktop/commit/f03ea69a7694baafd1392ee27b617ee092e6f6b2))

## [1.1.0](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.0.0...v1.1.0) (2026-03-11)


### Features

* add ArcBoxHelper privileged helper for root-level operations ([61f93f0](https://github.com/arcboxlabs/arcbox-desktop/commit/61f93f00812e1ade0f347dddf7eb403faf606322))
* **ci:** add release-please for automated version management ([3dadf72](https://github.com/arcboxlabs/arcbox-desktop/commit/3dadf72db95495b873b5075a176f8493a700957b))
* **sparkle:** integrate Sparkle auto-update ([#7](https://github.com/arcboxlabs/arcbox-desktop/issues/7)) ([d66b954](https://github.com/arcboxlabs/arcbox-desktop/commit/d66b95498b81f3769847dbae8e3bc5c8b23c2921))


### Bug Fixes

* add missing await on SMAppService.unregister() in teardown path ([17176e4](https://github.com/arcboxlabs/arcbox-desktop/commit/17176e47992ac82294c235c0396a85dc5d80368a))
* correct daemon socket paths to match runtime directory ([bbc3fe7](https://github.com/arcboxlabs/arcbox-desktop/commit/bbc3fe74a5d3decce6461a5b34400d350beeace3))
* **packaging:** deep-sign bundle first then re-sign daemon with entitlements ([ddce0c7](https://github.com/arcboxlabs/arcbox-desktop/commit/ddce0c75e7e28daa61fbda324ceac49503ce5df0))
* **packaging:** re-sign outer app after daemon entitlement to refresh seal ([bbdbc96](https://github.com/arcboxlabs/arcbox-desktop/commit/bbdbc96241428f7d54dd7632dd6a1a2a1fecd6aa))
* **packaging:** sign ArcBoxHelper and fetch notarization log on failure ([013952b](https://github.com/arcboxlabs/arcbox-desktop/commit/013952b558af2c1028a05a8c16697e70a9ca46a5))
* **packaging:** sign daemon helper with virtualization entitlement before app bundle ([345c6a1](https://github.com/arcboxlabs/arcbox-desktop/commit/345c6a1dca7ad70b397c5f5526bb303ae534335e))

## Changelog
