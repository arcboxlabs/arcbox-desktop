# Changelog

## [1.14.0](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.13.3...v1.14.0) (2026-03-26)


### Features

* remove daemon plist log paths (companion to arcbox[#99](https://github.com/arcboxlabs/arcbox-desktop/issues/99)) ([#64](https://github.com/arcboxlabs/arcbox-desktop/issues/64)) ([af2780c](https://github.com/arcboxlabs/arcbox-desktop/commit/af2780cb468ed362f5a53f1f497488d147c10f17))


### Refactoring

* rename app from "ArcBox Desktop" to "ArcBox" ([#78](https://github.com/arcboxlabs/arcbox-desktop/issues/78)) ([26c374c](https://github.com/arcboxlabs/arcbox-desktop/commit/26c374c2f7512fa1e6abf7b621e1fb390b1b9b9d))

## [1.13.3](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.13.2...v1.13.3) (2026-03-26)


### Miscellaneous

* bump arcbox version to v0.3.9 ([#77](https://github.com/arcboxlabs/arcbox-desktop/issues/77)) ([02197cd](https://github.com/arcboxlabs/arcbox-desktop/commit/02197cd55afeaa31b5b0e1fd226b4ad5a5655d29))

## [1.13.2](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.13.1...v1.13.2) (2026-03-26)


### Miscellaneous

* bump arcbox version to v0.3.8 ([#76](https://github.com/arcboxlabs/arcbox-desktop/issues/76)) ([764e486](https://github.com/arcboxlabs/arcbox-desktop/commit/764e4861af947957515d5121a85a0d36c7f8161c))

## [1.13.1](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.13.0...v1.13.1) (2026-03-25)


### Miscellaneous

* bump arcbox version to v0.3.7 ([#74](https://github.com/arcboxlabs/arcbox-desktop/issues/74)) ([b243449](https://github.com/arcboxlabs/arcbox-desktop/commit/b2434490a9bf793484ff0655fe7390d82017b7be))

## [1.13.0](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.12.3...v1.13.0) (2026-03-24)


### Features

* **ci:** update Dub download short links after stable release ([#71](https://github.com/arcboxlabs/arcbox-desktop/issues/71)) ([768027d](https://github.com/arcboxlabs/arcbox-desktop/commit/768027d04fb46edcd5e496912f131f0130956b8f))

## [1.12.3](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.12.2...v1.12.3) (2026-03-23)


### Bug Fixes

* inject SUFeedURL via PlistBuddy instead of xcodebuild build setting ([#69](https://github.com/arcboxlabs/arcbox-desktop/issues/69)) ([2ff1655](https://github.com/arcboxlabs/arcbox-desktop/commit/2ff1655b7664cad599e18184372403c28cc1ae97))

## [1.12.2](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.12.1...v1.12.2) (2026-03-23)


### Miscellaneous

* bump arcbox version to v0.3.5 ([#66](https://github.com/arcboxlabs/arcbox-desktop/issues/66)) ([cc27948](https://github.com/arcboxlabs/arcbox-desktop/commit/cc2794860c59c21e2891b334beaa68ed446d1bc0))

## [1.12.1](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.12.0...v1.12.1) (2026-03-22)


### Bug Fixes

* cache negative icon lookups and include iconURL in equality check ([5823203](https://github.com/arcboxlabs/arcbox-desktop/commit/58232033075d89cc9aa28705741da102623276ce))
* cache negative icon lookups to avoid repeated RPCs ([ab7214e](https://github.com/arcboxlabs/arcbox-desktop/commit/ab7214e581b007be9ef296a668df9829e4533b50))
* include iconURL in ContainerViewModel equality check ([d28d8a8](https://github.com/arcboxlabs/arcbox-desktop/commit/d28d8a869a8406bb0a7cd52995490412b3326ba6))

## [1.12.0](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.11.0...v1.12.0) (2026-03-22)


### Features

* integrate IconService for container/image icon display ([#61](https://github.com/arcboxlabs/arcbox-desktop/issues/61)) ([384acd1](https://github.com/arcboxlabs/arcbox-desktop/commit/384acd109f02028d524eb57888ac4b58bb855441))

## [1.11.0](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.10.2...v1.11.0) (2026-03-22)


### Features

* DNS-based container domain resolution & UI improvements ([#35](https://github.com/arcboxlabs/arcbox-desktop/issues/35)) ([402012f](https://github.com/arcboxlabs/arcbox-desktop/commit/402012f6456ca2d6b64c0da772758aae95fcc945))


### Miscellaneous

* bump arcbox version to v0.3.3 ([#60](https://github.com/arcboxlabs/arcbox-desktop/issues/60)) ([c2fcb71](https://github.com/arcboxlabs/arcbox-desktop/commit/c2fcb7114b36211fe280773331335d792731e9b4))

## [1.10.2](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.10.1...v1.10.2) (2026-03-21)


### Refactoring

* daemon self-provisioning — desktop becomes pure gRPC display layer ([#57](https://github.com/arcboxlabs/arcbox-desktop/issues/57)) ([c173980](https://github.com/arcboxlabs/arcbox-desktop/commit/c173980e3645019bf3e239afc81ecf94dd7411bb))


### Miscellaneous

* bump arcbox version to v0.3.1 ([#54](https://github.com/arcboxlabs/arcbox-desktop/issues/54)) ([e05f711](https://github.com/arcboxlabs/arcbox-desktop/commit/e05f71146dbc98a6cd790794aff8c65b32b73f71))
* bump arcbox version to v0.3.2 ([#56](https://github.com/arcboxlabs/arcbox-desktop/issues/56)) ([2cbf8ed](https://github.com/arcboxlabs/arcbox-desktop/commit/2cbf8ed8d266619d366e79dc1e7f808c7674858e))

## [1.10.1](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.10.0...v1.10.1) (2026-03-18)


### Bug Fixes

* **startup:** reorder preconditions to prevent daemon race conditions ([c856a1e](https://github.com/arcboxlabs/arcbox-desktop/commit/c856a1e8e14116dc36d4db7d7fdb6eff9f8b1f89))
* **startup:** throw on enumerator failure, restore test target ([5d48f94](https://github.com/arcboxlabs/arcbox-desktop/commit/5d48f94501fa8c2ce53ae41de25bb14635cc7ab6))


### Miscellaneous

* bump arcbox version to v0.2.7 ([#52](https://github.com/arcboxlabs/arcbox-desktop/issues/52)) ([01c7950](https://github.com/arcboxlabs/arcbox-desktop/commit/01c7950e875e87539833949627b9419cf866de1c))

## [1.10.0](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.9.6...v1.10.0) (2026-03-17)


### Features

* **helper:** add pure mutation CLI commands (add-interface, remove-interface) ([62ea523](https://github.com/arcboxlabs/arcbox-desktop/commit/62ea5237ab3d3396d36e486bd27191fd649ab9f9))

## [1.9.6](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.9.5...v1.9.6) (2026-03-17)


### Bug Fixes

* **helper:** check approval status after initial registration ([7c424bf](https://github.com/arcboxlabs/arcbox-desktop/commit/7c424bffbee2a58d86db59dcc22f54fda20e7131))
* **helper:** query bridge interfaces individually for Address cache ([0d5eb5a](https://github.com/arcboxlabs/arcbox-desktop/commit/0d5eb5ac726761bd4587549a7a382359352c6739))


### Miscellaneous

* bump arcbox version to v0.2.5 ([#48](https://github.com/arcboxlabs/arcbox-desktop/issues/48)) ([8af214a](https://github.com/arcboxlabs/arcbox-desktop/commit/8af214a4e77363902afb5b1b031b40c473769b6f))


### Documentation

* add README ([8c2f5a6](https://github.com/arcboxlabs/arcbox-desktop/commit/8c2f5a629f151fef006cd3b33c81842ad9d1f495))

## [1.9.5](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.9.4...v1.9.5) (2026-03-17)


### Bug Fixes

* **boot:** use SHA256 to detect and replace stale agent/runtime binaries ([498216a](https://github.com/arcboxlabs/arcbox-desktop/commit/498216a3bda877118205164c272a5d9c10ed6575))
* **helper:** handle non-bridge stale routes in ensureRoute/removeRoute ([cfc91d6](https://github.com/arcboxlabs/arcbox-desktop/commit/cfc91d6eaa10f0706e7e30d3c11c152a59ec24c6))

## [1.9.4](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.9.3...v1.9.4) (2026-03-17)


### Miscellaneous

* bump arcbox version to v0.2.4 ([#44](https://github.com/arcboxlabs/arcbox-desktop/issues/44)) ([2cc3c60](https://github.com/arcboxlabs/arcbox-desktop/commit/2cc3c601ae64f0b48387e63f5c3f90b9a5737fcc))
* **release:** unhide chore/docs/ci from changelog and version bumps ([83f3b73](https://github.com/arcboxlabs/arcbox-desktop/commit/83f3b7349c961c6f64c5af0adc6f83750b404310))

## [1.9.3](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.9.2...v1.9.3) (2026-03-16)


### Bug Fixes

* **helper:** force re-register helper on app update ([deda0ca](https://github.com/arcboxlabs/arcbox-desktop/commit/deda0ca24c7efc1b32a834e6307d7784e3c0eed8))

## [1.9.2](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.9.1...v1.9.2) (2026-03-16)


### Bug Fixes

* **helper:** normalize MAC addresses before bridge resolution ([162c014](https://github.com/arcboxlabs/arcbox-desktop/commit/162c014b224558f5d989ede27bf070baeb53f6f0))

## [1.9.1](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.9.0...v1.9.1) (2026-03-16)


### Bug Fixes

* **build:** remove restricted com.apple.vm.networking entitlement ([75d4060](https://github.com/arcboxlabs/arcbox-desktop/commit/75d4060dc9ff5beb83094c21f72a27b97d01420c))

## [1.9.0](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.8.3...v1.9.0) (2026-03-16)


### Features

* **net:** move route ownership to daemon, add helperctl + smart route ops ([e6076e0](https://github.com/arcboxlabs/arcbox-desktop/commit/e6076e06300092e89ae248f22654583fba179ccb))


### Bug Fixes

* **net:** bump protocol version, real error reporting, vmnet bridge identity ([93c1003](https://github.com/arcboxlabs/arcbox-desktop/commit/93c10032110e03db477eeb17d5257bddc967b143))
* **net:** route retry/reconcile and cleanup on shutdown ([85fb92c](https://github.com/arcboxlabs/arcbox-desktop/commit/85fb92c2e4ee2c09cd04a830c5b95888efd17950))


### Refactoring

* **helper:** merge helperctl into ArcBoxHelper as route subcommand ([e4b4a22](https://github.com/arcboxlabs/arcbox-desktop/commit/e4b4a22a3cd906b2165a632a6012288c21f593c9))

## [1.8.3](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.8.2...v1.8.3) (2026-03-16)


### Bug Fixes

* **net:** add com.apple.vm.networking entitlement for vmnet bridge ([d106943](https://github.com/arcboxlabs/arcbox-desktop/commit/d10694321a20143f657adf267c8d96bdfa4c1a85))

## [1.8.2](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.8.1...v1.8.2) (2026-03-16)


### Bug Fixes

* add explicit self in closure captures for ContainersVM and ImagesVM ([164d069](https://github.com/arcboxlabs/arcbox-desktop/commit/164d069d0d48493f8b384297e20e0b7fe12be5f1))
* resolve CI build errors in observability code ([c1004fb](https://github.com/arcboxlabs/arcbox-desktop/commit/c1004fbca85bc7fcaa1622f2fcef7b68632d8ed1))

## [1.8.1](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.8.0...v1.8.1) (2026-03-16)


### Bug Fixes

* **helper:** remove attachScreenshot (unavailable in macOS CLI tools) ([14c3527](https://github.com/arcboxlabs/arcbox-desktop/commit/14c352723607817ed98cc0054053dc291472a6ad))

## [1.8.0](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.7.1...v1.8.0) (2026-03-15)


### Features

* **net:** L3 direct routing via vmnet bridge and proxy ARP ([e0238f5](https://github.com/arcboxlabs/arcbox-desktop/commit/e0238f555d76d9cfd08d783a8759e549a299a296))

## [1.7.1](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.7.0...v1.7.1) (2026-03-15)


### Bug Fixes

* **ci:** use vars context instead of secrets in workflow if condition ([5e11e55](https://github.com/arcboxlabs/arcbox-desktop/commit/5e11e551efb176e44bec26a24086762c17b0c841))

## [1.7.0](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.6.1...v1.7.0) (2026-03-15)


### Features

* **helper:** add route management for L3 direct routing ([10ea4d3](https://github.com/arcboxlabs/arcbox-desktop/commit/10ea4d3c5de646c05f2fe5c1234f7289f906386a))


### Refactoring

* improve release workflow DRY and reliability ([f782c14](https://github.com/arcboxlabs/arcbox-desktop/commit/f782c143096a48c3bb58131ebe8a98fa625b405f))

## [1.6.1](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.6.0...v1.6.1) (2026-03-15)


### Bug Fixes

* correct DEVELOPMENT_TEAM to 422ACSY6Y5 for all targets ([85e57c5](https://github.com/arcboxlabs/arcbox-desktop/commit/85e57c572b2df4fc43b1ac9b0b83b860adc23e84))

## [1.6.0](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.5.1...v1.6.0) (2026-03-14)


### Features

* Linux Machines module UI ([#18](https://github.com/arcboxlabs/arcbox-desktop/issues/18)) ([1676009](https://github.com/arcboxlabs/arcbox-desktop/commit/1676009d0ba23e4f9f1c67933897bb1dcdb322e1))

## [1.5.1](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.5.0...v1.5.1) (2026-03-14)


### Bug Fixes

* trigger release for bundle ID migration ([506e3e7](https://github.com/arcboxlabs/arcbox-desktop/commit/506e3e7b5d95ce5e425ae04942b5911244e424fb))

## [1.5.0](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.4.3...v1.5.0) (2026-03-13)


### Features

* add abctl CLI to build/sign pipeline and update dev team ([8b108c6](https://github.com/arcboxlabs/arcbox-desktop/commit/8b108c6c58a37271457af29b99553af1b166cc4a))
* add ArcBoxClient local Swift package for gRPC daemon communication ([5bf00d5](https://github.com/arcboxlabs/arcbox-desktop/commit/5bf00d597a3ea4e7eb17ef0a330c952b478a4ed0))
* add ArcBoxHelper privileged helper for root-level operations ([61f93f0](https://github.com/arcboxlabs/arcbox-desktop/commit/61f93f00812e1ade0f347dddf7eb403faf606322))
* add DockerClient package with swift-openapi-generator ([aa2e4c3](https://github.com/arcboxlabs/arcbox-desktop/commit/aa2e4c3a5e86868195936badc3af0c253cdb8a2d))
* add search filtering for containers, images, and volumes lists ([fb29852](https://github.com/arcboxlabs/arcbox-desktop/commit/fb2985295c7462d8a6d5dd667eb88d11a86572fe))
* add Unix socket transport and integrate Docker Engine API ([f2f86c3](https://github.com/arcboxlabs/arcbox-desktop/commit/f2f86c368adf4a97e95a84d9ff624f967e8b785f))
* **app:** auto-register CLI on first launch via `arcbox setup install` ([9d3b291](https://github.com/arcboxlabs/arcbox-desktop/commit/9d3b2913813a2e2d1f957824ca214cda9a1f3919))
* auto-install Docker CLI tools and enable context on app launch ([4561d69](https://github.com/arcboxlabs/arcbox-desktop/commit/4561d699e89f5b133d1502ab7e52b3b48ea1b5ce))
* **boot:** add BootAssetManager and integrate into app startup ([1ee0840](https://github.com/arcboxlabs/arcbox-desktop/commit/1ee08409a0a2a7420234bd622cfd46805746c366))
* bundle and seed arcbox-agent for daemon startup ([e027508](https://github.com/arcboxlabs/arcbox-desktop/commit/e027508c6ce2de6f35c5a787587bac50f687ea01))
* **ci:** add code signing and notarization to release workflow ([e6ae4ab](https://github.com/arcboxlabs/arcbox-desktop/commit/e6ae4ab11fbaf9b656eda67e416f5460cc5fe003))
* **ci:** add DMG release workflow ([cbd39d6](https://github.com/arcboxlabs/arcbox-desktop/commit/cbd39d673ac9f566ce9bad6415a542b9023570c6))
* **ci:** add release-please for automated version management ([3dadf72](https://github.com/arcboxlabs/arcbox-desktop/commit/3dadf72db95495b873b5075a176f8493a700957b))
* **ci:** pin arcbox version via arcbox.version file ([387d73d](https://github.com/arcboxlabs/arcbox-desktop/commit/387d73d799dc982bfa04405dd92924af6ed14b10))
* **cli:** update CLIRunner for abctl binary rename ([2e5e01a](https://github.com/arcboxlabs/arcbox-desktop/commit/2e5e01a06673c5abb7084646084aaabe01b39775))
* **containers:** implement local rootfs filesystem browser ([8be7bc8](https://github.com/arcboxlabs/arcbox-desktop/commit/8be7bc8ca6e3d05551f3b56cb7f29657396a6bdf))
* **containers:** implement real container logs with streaming support ([356790f](https://github.com/arcboxlabs/arcbox-desktop/commit/356790ffc61138d132e7028e96d0c65154714e72))
* **containers:** implement real interactive terminal with SwiftTerm ([9962bba](https://github.com/arcboxlabs/arcbox-desktop/commit/9962bba4857dfc1b25b72a1ae39e900ec91a9393))
* **containers:** improve list UI with loading states, sections, and group actions ([ebf306d](https://github.com/arcboxlabs/arcbox-desktop/commit/ebf306d6195b420ddd4e46b9fedb6daff838a366))
* **containers:** match compose group header height to container row\n\nIncrease ContainerGroupView header frame height from 36 to 44 so compose\ngroup cells align visually with standalone container rows in the list. ([9fc8669](https://github.com/arcboxlabs/arcbox-desktop/commit/9fc8669b4559c6ee56f3c0c95414e0a8dd347866))
* daemon lifecycle management via SMAppService ([da243aa](https://github.com/arcboxlabs/arcbox-desktop/commit/da243aa2b2287d3ce3235044e90f0a3c48c900f8))
* **delete:** wire up delete for images, volumes, and networks ([2acec3b](https://github.com/arcboxlabs/arcbox-desktop/commit/2acec3bf9c18bb5bde6ff5f8e0ab84693aaa5cd1))
* **dmg:** embed Docker tools, completions, and pstramp ([f9ff1fc](https://github.com/arcboxlabs/arcbox-desktop/commit/f9ff1fcb478f4033b523ca95a37042130bdb96b9))
* **events:** add real-time Docker events monitoring via DockerEventMonitor ([8c89d13](https://github.com/arcboxlabs/arcbox-desktop/commit/8c89d132833128818fe0ffa8a881075eb4a14d96))
* **images:** implement local rootfs filesystem browser for images ([bbb9553](https://github.com/arcboxlabs/arcbox-desktop/commit/bbb9553fc70e984778d1c63b356f9ea499e52335))
* **images:** implement real interactive terminal for images ([c3cd532](https://github.com/arcboxlabs/arcbox-desktop/commit/c3cd5322fd0d4ea8ca54b633e07d60f328ba9d07))
* integrate Sparkle auto-update framework ([#6](https://github.com/arcboxlabs/arcbox-desktop/issues/6)) ([df2d7a4](https://github.com/arcboxlabs/arcbox-desktop/commit/df2d7a4176d763bd1932d272898ea38224e030ec))
* **network:** add new button to create new network ([5e76b3b](https://github.com/arcboxlabs/arcbox-desktop/commit/5e76b3b65dcfafcd9e8184600fa019c268518161))
* **release:** add Backblaze B2 CDN distribution and Sparkle EdDSA signing ([e636df6](https://github.com/arcboxlabs/arcbox-desktop/commit/e636df6462f42e43d6db5bc630eb28a211e3c59e))
* **sparkle:** integrate Sparkle auto-update ([#7](https://github.com/arcboxlabs/arcbox-desktop/issues/7)) ([d66b954](https://github.com/arcboxlabs/arcbox-desktop/commit/d66b95498b81f3769847dbae8e3bc5c8b23c2921))
* stream Docker tool install progress via DockerToolSetupManager ([8244db8](https://github.com/arcboxlabs/arcbox-desktop/commit/8244db898bb5824371d979f632113a30f5eb0735))
* **ui:** add app icon assets ([06a195d](https://github.com/arcboxlabs/arcbox-desktop/commit/06a195d0402bc7c83a127e5e27d6ad468af1aa28))
* **ui:** add copy button and text selection to CommandHint ([a642cfd](https://github.com/arcboxlabs/arcbox-desktop/commit/a642cfd194b78567701ce63a723ef222f8795cbf))
* **ui:** add create dialogs for volumes, images, and networks ([3ed1ab7](https://github.com/arcboxlabs/arcbox-desktop/commit/3ed1ab73d428eba4e7e42fc83dfdd0e10be1bcf5))
* **ui:** add Kubernetes pods and services sections ([2448d64](https://github.com/arcboxlabs/arcbox-desktop/commit/2448d641a32022496d1b6cff5a1d3bce5995c27c))
* **ui:** add localhost link button and domain display for containers with ports ([22da16e](https://github.com/arcboxlabs/arcbox-desktop/commit/22da16efadbd119baee2fc965c503728eabcdc48))
* **ui:** add Sandbox section with Sandboxes and Templates ([5ea9092](https://github.com/arcboxlabs/arcbox-desktop/commit/5ea9092d307cd2975b86eafc515eca19037992c5))
* **ui:** add SwiftUI port of arcbox-desktop UI ([0ba79b1](https://github.com/arcboxlabs/arcbox-desktop/commit/0ba79b110c1eaf8bebd8da6f6c21ae27bd2d7a23))
* **ui:** add the zebra line and optimize the ui of filesystem browser ([3c4b5c9](https://github.com/arcboxlabs/arcbox-desktop/commit/3c4b5c99b13a639d0b0802e00d318f70e9625631))
* **ui:** flatten sort menu into single-level with sections ([a0c38c4](https://github.com/arcboxlabs/arcbox-desktop/commit/a0c38c4fd94ea7c882de42aa4612088e0bbb9090))
* **ui:** implement container detail tabs (Info, Logs, Terminal, Files) ([0129457](https://github.com/arcboxlabs/arcbox-desktop/commit/012945734cf53e18f14ba6bb2169f26e0846ac79))
* **ui:** implement detail tabs for volumes, images, and networks ([f97e7ef](https://github.com/arcboxlabs/arcbox-desktop/commit/f97e7ef34aac56bc3a4c6d1bebdbdc356a117327))
* **ui:** implement sort menu logic across all list views ([10c6f8a](https://github.com/arcboxlabs/arcbox-desktop/commit/10c6f8af193dd29b06f768626a7a738e42e9b0ad))
* **ui:** set menu bar app name to ArcBox Desktop ([a049605](https://github.com/arcboxlabs/arcbox-desktop/commit/a049605bff515a764830cf6bd9d0cb7a63d05f77))
* **ui:** show decimal precision for size display across volumes and images ([58d63ba](https://github.com/arcboxlabs/arcbox-desktop/commit/58d63bab4cd3419d4185abbd91585cf2cf9c28be))
* **ui:** show loading indicator during daemon startup and shutdown ([05b4549](https://github.com/arcboxlabs/arcbox-desktop/commit/05b45491629e695111cfc2dc765743bfb749e8b0))
* **volumes:** implement local rootfs filesystem browser for volumes ([d350189](https://github.com/arcboxlabs/arcbox-desktop/commit/d3501890df17e21c6160507a41303fe04f9d3afb))


### Bug Fixes

* add missing await on SMAppService.unregister() in teardown path ([17176e4](https://github.com/arcboxlabs/arcbox-desktop/commit/17176e47992ac82294c235c0396a85dc5d80368a))
* add refactor/perf to release-please changelog sections ([702ea8c](https://github.com/arcboxlabs/arcbox-desktop/commit/702ea8c6c1edddcfa59052545430a4f456bd1a0e))
* bundle all runtime binaries in DMG via abctl boot prefetch ([8754160](https://github.com/arcboxlabs/arcbox-desktop/commit/8754160efb6081f9bafb979eca92f7b4b895f8ba))
* **ci:** add package-dmg.sh and fix workflow references ([ebb6b18](https://github.com/arcboxlabs/arcbox-desktop/commit/ebb6b182e4fee7fb718dfb7549f9f0bc956238ce))
* **ci:** auto-download latest arcbox release when ref is not a tag ([8fb77c5](https://github.com/arcboxlabs/arcbox-desktop/commit/8fb77c5d881b871d378d3c08b700d7ad2caff102))
* **ci:** create empty Local.xcconfig for CI builds ([a2e0408](https://github.com/arcboxlabs/arcbox-desktop/commit/a2e0408422ebd6e358123699c92aa3dd091c6c8a))
* **ci:** create release as draft until DMG is attached ([81e6077](https://github.com/arcboxlabs/arcbox-desktop/commit/81e607756fd8f90a426150a1d9ee27af3cf50afe))
* **ci:** extract arcbox-agent from release assets in DMG workflow ([5f15268](https://github.com/arcboxlabs/arcbox-desktop/commit/5f15268afdec55b43500b5e278ffc88cd39ead62))
* **ci:** extract tarball before searching for arcbox binaries ([175cf21](https://github.com/arcboxlabs/arcbox-desktop/commit/175cf21507d9be026b4a32b8b9f2fba878ce218c))
* **ci:** improve Sparkle signing error visibility and use vars for public key ([fff55ee](https://github.com/arcboxlabs/arcbox-desktop/commit/fff55ee64e0436faee2964b53785db7b8b8dacd9))
* **ci:** remove draft flag from release-please config ([06b67e8](https://github.com/arcboxlabs/arcbox-desktop/commit/06b67e8ed54133cacc08701d33680dd97069f75a))
* **ci:** remove unnecessary token for public arcbox repo checkout ([cc4196e](https://github.com/arcboxlabs/arcbox-desktop/commit/cc4196e17464ba13805830657b67e53f54265a89))
* **ci:** rename arcbox checkout path to avoid case-insensitive FS collision ([8d92555](https://github.com/arcboxlabs/arcbox-desktop/commit/8d925554175b25a2ea9ddc7cf78b95084741f4f1))
* **ci:** resolve SPM package name collision and shallow clone build number ([f03ea69](https://github.com/arcboxlabs/arcbox-desktop/commit/f03ea69a7694baafd1392ee27b617ee092e6f6b2))
* **ci:** revert SPARKLE_PUBLIC_KEY back to secrets ([a632971](https://github.com/arcboxlabs/arcbox-desktop/commit/a63297116684e06d7483b326a775d4272aa5db60))
* **ci:** skip Rust build when pre-built binaries are available ([c9e5163](https://github.com/arcboxlabs/arcbox-desktop/commit/c9e516389c92f7f44c8f5e998f737cc9cbb645f6))
* **ci:** skip SwiftPM plugin validation for OpenAPIGenerator ([#4](https://github.com/arcboxlabs/arcbox-desktop/issues/4)) ([3b9b0cf](https://github.com/arcboxlabs/arcbox-desktop/commit/3b9b0cf2e637bb8c873d269df9cf26417906f4bd))
* **ci:** symlink arcbox for Xcode build phase script ([a03fb7d](https://github.com/arcboxlabs/arcbox-desktop/commit/a03fb7d4a266ede23f4cfcb213f6b0d6bd6884cd))
* **ci:** use printf instead of echo for Sparkle private key to avoid trailing newline ([52f7d97](https://github.com/arcboxlabs/arcbox-desktop/commit/52f7d970f71427254df0a404d06d841dd543f4fc))
* **ci:** use Xcode global default to skip plugin validation ([8059c2c](https://github.com/arcboxlabs/arcbox-desktop/commit/8059c2c3eb0b96b3591cd7111082977e70e04f67))
* **client:** move all Process/IO off MainActor to prevent UI freezes ([bf42a45](https://github.com/arcboxlabs/arcbox-desktop/commit/bf42a458995d08c8e0ff74cdf3c99d258cccbcf7))
* **containers:** align ArcBox rootfs and socket resolution ([e552dfe](https://github.com/arcboxlabs/arcbox-desktop/commit/e552dfedd8c72e2f7f54c531730e6f76a1a4e539))
* **containers:** dim compose group header when all containers are stopped\n\nApply muted foreground colors to the layer icon and project name in\nContainerGroupView when no containers in the group are running. This\nmakes it visually consistent with stopped standalone container rows\nand easier to distinguish running groups from stopped ones at a glance. ([fa2f653](https://github.com/arcboxlabs/arcbox-desktop/commit/fa2f6537678687d4cc1d331877cd7e8d5221e00d))
* **containers:** refresh terminal when switching containers ([d79478d](https://github.com/arcboxlabs/arcbox-desktop/commit/d79478d57d3d769b02f53729d6103042171d2778))
* **containers:** show domain/ip/mounts reliably in info panel ([b236498](https://github.com/arcboxlabs/arcbox-desktop/commit/b23649821ae0b863301cc9742c9be10014a79ec2))
* correct daemon socket paths to match runtime directory ([bbc3fe7](https://github.com/arcboxlabs/arcbox-desktop/commit/bbc3fe74a5d3decce6461a5b34400d350beeace3))
* **daemon:** avoid blocking main thread in reachability check and add fast path ([6d5dd93](https://github.com/arcboxlabs/arcbox-desktop/commit/6d5dd93e3802cfbc391c66a85d1066598a87d4fa))
* **docker:** fix volumes and images decoding errors, add volume size support ([424ca65](https://github.com/arcboxlabs/arcbox-desktop/commit/424ca65f33d1af660cbaa27ad37bbdc9fed2bac9))
* **docker:** handle TTY container logs without multiplexed framing ([274595c](https://github.com/arcboxlabs/arcbox-desktop/commit/274595c80d4e1d9a6fd873692c40286e108d0ef5))
* force SMAppService re-registration to resolve stale bundle paths ([f96f9c2](https://github.com/arcboxlabs/arcbox-desktop/commit/f96f9c2a63b11edb4d68cd8a516874c12e0e4ec2))
* **icon:** add standard macOS drop shadow to app icon ([264e052](https://github.com/arcboxlabs/arcbox-desktop/commit/264e052af8998ef40f1ff8f1e99a4ba635969f2e))
* **icon:** apply macOS HIG padding and corner radius to app icon ([6232d5b](https://github.com/arcboxlabs/arcbox-desktop/commit/6232d5b2f4b438dd05cfdb0a36d8c85f0424c290))
* **images:** resolve terminal hang when switching images or tabs ([c7a351d](https://github.com/arcboxlabs/arcbox-desktop/commit/c7a351d6eea6c2505ff7dae36bc90a0c6927d7c1))
* **init:** reactively create Docker/gRPC clients on daemon state change ([88c8675](https://github.com/arcboxlabs/arcbox-desktop/commit/88c8675d8f54cd4228ae3e3ef18459b4aae55fff))
* **logs:** avoid log gap between history and streaming phases ([7945b44](https://github.com/arcboxlabs/arcbox-desktop/commit/7945b44dc3453764b81636d963724cfb713d6fc1))
* **logs:** convert UTC timestamps to user's local timezone ([0220962](https://github.com/arcboxlabs/arcbox-desktop/commit/0220962400d0a7dca367a8314c99d8295776828a))
* **logs:** fix stream cancellation and error handling ([14c4adc](https://github.com/arcboxlabs/arcbox-desktop/commit/14c4adc2e1bc6467669faaa2557b78adf9841ed9))
* make helper setup non-blocking to prevent startup hang ([f9b6023](https://github.com/arcboxlabs/arcbox-desktop/commit/f9b6023d03a98c4cf453fe69ef431386f581ce10))
* **models:** use distantPast fallback for unparseable dates ([72cca5c](https://github.com/arcboxlabs/arcbox-desktop/commit/72cca5c28fef2c11344ab738edd8859b1b6576d3))
* **packaging:** deep-sign bundle first then re-sign daemon with entitlements ([ddce0c7](https://github.com/arcboxlabs/arcbox-desktop/commit/ddce0c75e7e28daa61fbda324ceac49503ce5df0))
* **packaging:** embed boot-assets into app bundle ([143faa7](https://github.com/arcboxlabs/arcbox-desktop/commit/143faa758b949539968048dd9edb2b12889fe590))
* **packaging:** re-sign outer app after daemon entitlement to refresh seal ([bbdbc96](https://github.com/arcboxlabs/arcbox-desktop/commit/bbdbc96241428f7d54dd7632dd6a1a2a1fecd6aa))
* **packaging:** sign ArcBoxHelper and fetch notarization log on failure ([013952b](https://github.com/arcboxlabs/arcbox-desktop/commit/013952b558af2c1028a05a8c16697e70a9ca46a5))
* **packaging:** sign daemon helper with virtualization entitlement before app bundle ([345c6a1](https://github.com/arcboxlabs/arcbox-desktop/commit/345c6a1dca7ad70b397c5f5526bb303ae534335e))
* resolve ArcBoxHelper XPC daemon launch failures ([#12](https://github.com/arcboxlabs/arcbox-desktop/issues/12)) ([4623cdd](https://github.com/arcboxlabs/arcbox-desktop/commit/4623cdd9b10b8fbcba6474a4264d73964d71e6f7))
* **terminal:** make reconnect button actually reconnect ([199e1a3](https://github.com/arcboxlabs/arcbox-desktop/commit/199e1a3d41fffe19c1d5f0e20f433e8c213192e9))
* **terminal:** use setString for clipboard copy ([cbb944c](https://github.com/arcboxlabs/arcbox-desktop/commit/cbb944c22b04a618c37edec99352454876eaea73))
* trigger release workflow on release event from release-please ([ee414a0](https://github.com/arcboxlabs/arcbox-desktop/commit/ee414a00f7c70d1f834464f25c7addda8e579cf2))
* **ui:** allow resizable content column in NavigationSplitView ([72fb81d](https://github.com/arcboxlabs/arcbox-desktop/commit/72fb81d1519d4875145ef5a479fe71c158c695f7))
* **ui:** resolve merge conflict in ContainersListView and use shared environment ViewModel ([da1c61a](https://github.com/arcboxlabs/arcbox-desktop/commit/da1c61ac02da1b83cb369116935e3368d5afbe2f))
* **ui:** unify list row selection style and panel width ([2e8deeb](https://github.com/arcboxlabs/arcbox-desktop/commit/2e8deeb7340593d8876e14a067cc5f777cc12ed3))
* **ui:** use fixed column widths in NavigationSplitView ([3e33a37](https://github.com/arcboxlabs/arcbox-desktop/commit/3e33a379653fd8560198331fcbaff9155d605675))
* **ui:** use mount content for info tab refresh key ([a1cf86d](https://github.com/arcboxlabs/arcbox-desktop/commit/a1cf86d134784c5dab55f8ffd1384b340c08738a))


### Refactoring

* **boot:** rewrite BootAssetManager to consume CLI JSON output ([577b304](https://github.com/arcboxlabs/arcbox-desktop/commit/577b3046c2eed7b1acf202d4cef0c4cc0f306b90))
* **boot:** rewrite BootAssetManager to consume CLI JSON output ([#5](https://github.com/arcboxlabs/arcbox-desktop/issues/5)) ([d978537](https://github.com/arcboxlabs/arcbox-desktop/commit/d978537f05b11a77ef47daa5c00c2bfdba8ee331))
* **ci:** pass BUNDLE_ID and TEAM_ID from secrets to package script ([15fab83](https://github.com/arcboxlabs/arcbox-desktop/commit/15fab8321ec8ecf78d0c854945391c36792cd3d5))
* **daemon:** simplify startup to always register via SMAppService ([dd73296](https://github.com/arcboxlabs/arcbox-desktop/commit/dd73296d924d658ac50eec22c4f45533103deeb8))
* introduce StartupOrchestrator for structured startup ([#21](https://github.com/arcboxlabs/arcbox-desktop/issues/21)) ([08e5afa](https://github.com/arcboxlabs/arcbox-desktop/commit/08e5afaf206ed57fec893627de1a6bfe9a0aed10))
* **networks:** merge info and containers tabs into single-page layout ([99fe578](https://github.com/arcboxlabs/arcbox-desktop/commit/99fe578d59b6e0ee6f29dfba541e06bddf44da6e))
* remove SampleFileTreeView.swift ([4531125](https://github.com/arcboxlabs/arcbox-desktop/commit/4531125e604ef1b0c53a77f6a729bba52ea77229))
* remove unused sample data and use real Docker API for network containers ([d4877cc](https://github.com/arcboxlabs/arcbox-desktop/commit/d4877cce8228c845357938bbd7c07277f9303106))
* rename project from arcbox-desktop-swift to ArcBox ([c492d0c](https://github.com/arcboxlabs/arcbox-desktop/commit/c492d0c3f97b0cbd885527cf6165e1358686ceb2))
* reorganize app bundle layout to match OrbStack conventions ([2a5bf71](https://github.com/arcboxlabs/arcbox-desktop/commit/2a5bf716f3cab85ead81043bb0a49e34b52b2e75))
* **terminal:** extract TerminalBridge into shared component ([7857567](https://github.com/arcboxlabs/arcbox-desktop/commit/7857567a414318e405fd5407e9389e214e012c6b))
* **ui:** migrate to NavigationSplitView layout ([89a0626](https://github.com/arcboxlabs/arcbox-desktop/commit/89a0626470786cb57577440e09573a1792c07ac2))
* **ui:** migrate to three-column NavigationSplitView layout ([7e7e2de](https://github.com/arcboxlabs/arcbox-desktop/commit/7e7e2de21c5e93c942648b147de1df4a9367282c))
* **ui:** reorganize view file structure ([7a03840](https://github.com/arcboxlabs/arcbox-desktop/commit/7a03840123460edd853d07e850380ee22beaaf7c))
* **ui:** standardize detail view tab bar layout ([56b32c5](https://github.com/arcboxlabs/arcbox-desktop/commit/56b32c51211be6a16a82ffad1e794e06f74af509))
* **ui:** use native toolbar and navigation title for list views ([f374ed5](https://github.com/arcboxlabs/arcbox-desktop/commit/f374ed57d12114bfe4341ad6ab471ff6b7477210))
* **ui:** use native toolbar buttons across all views ([e190279](https://github.com/arcboxlabs/arcbox-desktop/commit/e190279e67bb0cd3ce4d448c95e2d89a5dac9508))

## [1.4.3](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.4.2...v1.4.3) (2026-03-13)


### Bug Fixes

* add refactor/perf to release-please changelog sections ([702ea8c](https://github.com/arcboxlabs/arcbox-desktop/commit/702ea8c6c1edddcfa59052545430a4f456bd1a0e))


### Refactoring

* introduce StartupOrchestrator for structured startup ([#21](https://github.com/arcboxlabs/arcbox-desktop/issues/21)) ([08e5afa](https://github.com/arcboxlabs/arcbox-desktop/commit/08e5afaf206ed57fec893627de1a6bfe9a0aed10))

## [1.4.2](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.4.1...v1.4.2) (2026-03-13)


### Bug Fixes

* **ci:** extract arcbox-agent from release assets in DMG workflow ([5f15268](https://github.com/arcboxlabs/arcbox-desktop/commit/5f15268afdec55b43500b5e278ffc88cd39ead62))

## [1.4.1](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.4.0...v1.4.1) (2026-03-13)


### Bug Fixes

* **ci:** remove draft flag from release-please config ([06b67e8](https://github.com/arcboxlabs/arcbox-desktop/commit/06b67e8ed54133cacc08701d33680dd97069f75a))

## [1.4.0](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.3.0...v1.4.0) (2026-03-13)


### Features

* add abctl CLI to build/sign pipeline and update dev team ([8b108c6](https://github.com/arcboxlabs/arcbox-desktop/commit/8b108c6c58a37271457af29b99553af1b166cc4a))
* add ArcBoxClient local Swift package for gRPC daemon communication ([5bf00d5](https://github.com/arcboxlabs/arcbox-desktop/commit/5bf00d597a3ea4e7eb17ef0a330c952b478a4ed0))
* add ArcBoxHelper privileged helper for root-level operations ([61f93f0](https://github.com/arcboxlabs/arcbox-desktop/commit/61f93f00812e1ade0f347dddf7eb403faf606322))
* add DockerClient package with swift-openapi-generator ([aa2e4c3](https://github.com/arcboxlabs/arcbox-desktop/commit/aa2e4c3a5e86868195936badc3af0c253cdb8a2d))
* add search filtering for containers, images, and volumes lists ([fb29852](https://github.com/arcboxlabs/arcbox-desktop/commit/fb2985295c7462d8a6d5dd667eb88d11a86572fe))
* add Unix socket transport and integrate Docker Engine API ([f2f86c3](https://github.com/arcboxlabs/arcbox-desktop/commit/f2f86c368adf4a97e95a84d9ff624f967e8b785f))
* **app:** auto-register CLI on first launch via `arcbox setup install` ([9d3b291](https://github.com/arcboxlabs/arcbox-desktop/commit/9d3b2913813a2e2d1f957824ca214cda9a1f3919))
* auto-install Docker CLI tools and enable context on app launch ([4561d69](https://github.com/arcboxlabs/arcbox-desktop/commit/4561d699e89f5b133d1502ab7e52b3b48ea1b5ce))
* **boot:** add BootAssetManager and integrate into app startup ([1ee0840](https://github.com/arcboxlabs/arcbox-desktop/commit/1ee08409a0a2a7420234bd622cfd46805746c366))
* bundle and seed arcbox-agent for daemon startup ([e027508](https://github.com/arcboxlabs/arcbox-desktop/commit/e027508c6ce2de6f35c5a787587bac50f687ea01))
* **ci:** add code signing and notarization to release workflow ([e6ae4ab](https://github.com/arcboxlabs/arcbox-desktop/commit/e6ae4ab11fbaf9b656eda67e416f5460cc5fe003))
* **ci:** add DMG release workflow ([cbd39d6](https://github.com/arcboxlabs/arcbox-desktop/commit/cbd39d673ac9f566ce9bad6415a542b9023570c6))
* **ci:** add release-please for automated version management ([3dadf72](https://github.com/arcboxlabs/arcbox-desktop/commit/3dadf72db95495b873b5075a176f8493a700957b))
* **ci:** pin arcbox version via arcbox.version file ([387d73d](https://github.com/arcboxlabs/arcbox-desktop/commit/387d73d799dc982bfa04405dd92924af6ed14b10))
* **cli:** update CLIRunner for abctl binary rename ([2e5e01a](https://github.com/arcboxlabs/arcbox-desktop/commit/2e5e01a06673c5abb7084646084aaabe01b39775))
* **containers:** implement local rootfs filesystem browser ([8be7bc8](https://github.com/arcboxlabs/arcbox-desktop/commit/8be7bc8ca6e3d05551f3b56cb7f29657396a6bdf))
* **containers:** implement real container logs with streaming support ([356790f](https://github.com/arcboxlabs/arcbox-desktop/commit/356790ffc61138d132e7028e96d0c65154714e72))
* **containers:** implement real interactive terminal with SwiftTerm ([9962bba](https://github.com/arcboxlabs/arcbox-desktop/commit/9962bba4857dfc1b25b72a1ae39e900ec91a9393))
* **containers:** improve list UI with loading states, sections, and group actions ([ebf306d](https://github.com/arcboxlabs/arcbox-desktop/commit/ebf306d6195b420ddd4e46b9fedb6daff838a366))
* **containers:** match compose group header height to container row\n\nIncrease ContainerGroupView header frame height from 36 to 44 so compose\ngroup cells align visually with standalone container rows in the list. ([9fc8669](https://github.com/arcboxlabs/arcbox-desktop/commit/9fc8669b4559c6ee56f3c0c95414e0a8dd347866))
* daemon lifecycle management via SMAppService ([da243aa](https://github.com/arcboxlabs/arcbox-desktop/commit/da243aa2b2287d3ce3235044e90f0a3c48c900f8))
* **delete:** wire up delete for images, volumes, and networks ([2acec3b](https://github.com/arcboxlabs/arcbox-desktop/commit/2acec3bf9c18bb5bde6ff5f8e0ab84693aaa5cd1))
* **dmg:** embed Docker tools, completions, and pstramp ([f9ff1fc](https://github.com/arcboxlabs/arcbox-desktop/commit/f9ff1fcb478f4033b523ca95a37042130bdb96b9))
* **events:** add real-time Docker events monitoring via DockerEventMonitor ([8c89d13](https://github.com/arcboxlabs/arcbox-desktop/commit/8c89d132833128818fe0ffa8a881075eb4a14d96))
* **images:** implement local rootfs filesystem browser for images ([bbb9553](https://github.com/arcboxlabs/arcbox-desktop/commit/bbb9553fc70e984778d1c63b356f9ea499e52335))
* **images:** implement real interactive terminal for images ([c3cd532](https://github.com/arcboxlabs/arcbox-desktop/commit/c3cd5322fd0d4ea8ca54b633e07d60f328ba9d07))
* integrate Sparkle auto-update framework ([#6](https://github.com/arcboxlabs/arcbox-desktop/issues/6)) ([df2d7a4](https://github.com/arcboxlabs/arcbox-desktop/commit/df2d7a4176d763bd1932d272898ea38224e030ec))
* **network:** add new button to create new network ([5e76b3b](https://github.com/arcboxlabs/arcbox-desktop/commit/5e76b3b65dcfafcd9e8184600fa019c268518161))
* **release:** add Backblaze B2 CDN distribution and Sparkle EdDSA signing ([e636df6](https://github.com/arcboxlabs/arcbox-desktop/commit/e636df6462f42e43d6db5bc630eb28a211e3c59e))
* **sparkle:** integrate Sparkle auto-update ([#7](https://github.com/arcboxlabs/arcbox-desktop/issues/7)) ([d66b954](https://github.com/arcboxlabs/arcbox-desktop/commit/d66b95498b81f3769847dbae8e3bc5c8b23c2921))
* stream Docker tool install progress via DockerToolSetupManager ([8244db8](https://github.com/arcboxlabs/arcbox-desktop/commit/8244db898bb5824371d979f632113a30f5eb0735))
* **ui:** add app icon assets ([06a195d](https://github.com/arcboxlabs/arcbox-desktop/commit/06a195d0402bc7c83a127e5e27d6ad468af1aa28))
* **ui:** add copy button and text selection to CommandHint ([a642cfd](https://github.com/arcboxlabs/arcbox-desktop/commit/a642cfd194b78567701ce63a723ef222f8795cbf))
* **ui:** add create dialogs for volumes, images, and networks ([3ed1ab7](https://github.com/arcboxlabs/arcbox-desktop/commit/3ed1ab73d428eba4e7e42fc83dfdd0e10be1bcf5))
* **ui:** add Kubernetes pods and services sections ([2448d64](https://github.com/arcboxlabs/arcbox-desktop/commit/2448d641a32022496d1b6cff5a1d3bce5995c27c))
* **ui:** add localhost link button and domain display for containers with ports ([22da16e](https://github.com/arcboxlabs/arcbox-desktop/commit/22da16efadbd119baee2fc965c503728eabcdc48))
* **ui:** add Sandbox section with Sandboxes and Templates ([5ea9092](https://github.com/arcboxlabs/arcbox-desktop/commit/5ea9092d307cd2975b86eafc515eca19037992c5))
* **ui:** add SwiftUI port of arcbox-desktop UI ([0ba79b1](https://github.com/arcboxlabs/arcbox-desktop/commit/0ba79b110c1eaf8bebd8da6f6c21ae27bd2d7a23))
* **ui:** add the zebra line and optimize the ui of filesystem browser ([3c4b5c9](https://github.com/arcboxlabs/arcbox-desktop/commit/3c4b5c99b13a639d0b0802e00d318f70e9625631))
* **ui:** flatten sort menu into single-level with sections ([a0c38c4](https://github.com/arcboxlabs/arcbox-desktop/commit/a0c38c4fd94ea7c882de42aa4612088e0bbb9090))
* **ui:** implement container detail tabs (Info, Logs, Terminal, Files) ([0129457](https://github.com/arcboxlabs/arcbox-desktop/commit/012945734cf53e18f14ba6bb2169f26e0846ac79))
* **ui:** implement detail tabs for volumes, images, and networks ([f97e7ef](https://github.com/arcboxlabs/arcbox-desktop/commit/f97e7ef34aac56bc3a4c6d1bebdbdc356a117327))
* **ui:** implement sort menu logic across all list views ([10c6f8a](https://github.com/arcboxlabs/arcbox-desktop/commit/10c6f8af193dd29b06f768626a7a738e42e9b0ad))
* **ui:** set menu bar app name to ArcBox Desktop ([a049605](https://github.com/arcboxlabs/arcbox-desktop/commit/a049605bff515a764830cf6bd9d0cb7a63d05f77))
* **ui:** show decimal precision for size display across volumes and images ([58d63ba](https://github.com/arcboxlabs/arcbox-desktop/commit/58d63bab4cd3419d4185abbd91585cf2cf9c28be))
* **ui:** show loading indicator during daemon startup and shutdown ([05b4549](https://github.com/arcboxlabs/arcbox-desktop/commit/05b45491629e695111cfc2dc765743bfb749e8b0))
* **volumes:** implement local rootfs filesystem browser for volumes ([d350189](https://github.com/arcboxlabs/arcbox-desktop/commit/d3501890df17e21c6160507a41303fe04f9d3afb))


### Bug Fixes

* add missing await on SMAppService.unregister() in teardown path ([17176e4](https://github.com/arcboxlabs/arcbox-desktop/commit/17176e47992ac82294c235c0396a85dc5d80368a))
* bundle all runtime binaries in DMG via abctl boot prefetch ([8754160](https://github.com/arcboxlabs/arcbox-desktop/commit/8754160efb6081f9bafb979eca92f7b4b895f8ba))
* **ci:** add package-dmg.sh and fix workflow references ([ebb6b18](https://github.com/arcboxlabs/arcbox-desktop/commit/ebb6b182e4fee7fb718dfb7549f9f0bc956238ce))
* **ci:** auto-download latest arcbox release when ref is not a tag ([8fb77c5](https://github.com/arcboxlabs/arcbox-desktop/commit/8fb77c5d881b871d378d3c08b700d7ad2caff102))
* **ci:** create empty Local.xcconfig for CI builds ([a2e0408](https://github.com/arcboxlabs/arcbox-desktop/commit/a2e0408422ebd6e358123699c92aa3dd091c6c8a))
* **ci:** create release as draft until DMG is attached ([81e6077](https://github.com/arcboxlabs/arcbox-desktop/commit/81e607756fd8f90a426150a1d9ee27af3cf50afe))
* **ci:** extract tarball before searching for arcbox binaries ([175cf21](https://github.com/arcboxlabs/arcbox-desktop/commit/175cf21507d9be026b4a32b8b9f2fba878ce218c))
* **ci:** improve Sparkle signing error visibility and use vars for public key ([fff55ee](https://github.com/arcboxlabs/arcbox-desktop/commit/fff55ee64e0436faee2964b53785db7b8b8dacd9))
* **ci:** remove unnecessary token for public arcbox repo checkout ([cc4196e](https://github.com/arcboxlabs/arcbox-desktop/commit/cc4196e17464ba13805830657b67e53f54265a89))
* **ci:** rename arcbox checkout path to avoid case-insensitive FS collision ([8d92555](https://github.com/arcboxlabs/arcbox-desktop/commit/8d925554175b25a2ea9ddc7cf78b95084741f4f1))
* **ci:** resolve SPM package name collision and shallow clone build number ([f03ea69](https://github.com/arcboxlabs/arcbox-desktop/commit/f03ea69a7694baafd1392ee27b617ee092e6f6b2))
* **ci:** revert SPARKLE_PUBLIC_KEY back to secrets ([a632971](https://github.com/arcboxlabs/arcbox-desktop/commit/a63297116684e06d7483b326a775d4272aa5db60))
* **ci:** skip Rust build when pre-built binaries are available ([c9e5163](https://github.com/arcboxlabs/arcbox-desktop/commit/c9e516389c92f7f44c8f5e998f737cc9cbb645f6))
* **ci:** skip SwiftPM plugin validation for OpenAPIGenerator ([#4](https://github.com/arcboxlabs/arcbox-desktop/issues/4)) ([3b9b0cf](https://github.com/arcboxlabs/arcbox-desktop/commit/3b9b0cf2e637bb8c873d269df9cf26417906f4bd))
* **ci:** symlink arcbox for Xcode build phase script ([a03fb7d](https://github.com/arcboxlabs/arcbox-desktop/commit/a03fb7d4a266ede23f4cfcb213f6b0d6bd6884cd))
* **ci:** use printf instead of echo for Sparkle private key to avoid trailing newline ([52f7d97](https://github.com/arcboxlabs/arcbox-desktop/commit/52f7d970f71427254df0a404d06d841dd543f4fc))
* **ci:** use Xcode global default to skip plugin validation ([8059c2c](https://github.com/arcboxlabs/arcbox-desktop/commit/8059c2c3eb0b96b3591cd7111082977e70e04f67))
* **client:** move all Process/IO off MainActor to prevent UI freezes ([bf42a45](https://github.com/arcboxlabs/arcbox-desktop/commit/bf42a458995d08c8e0ff74cdf3c99d258cccbcf7))
* **containers:** align ArcBox rootfs and socket resolution ([e552dfe](https://github.com/arcboxlabs/arcbox-desktop/commit/e552dfedd8c72e2f7f54c531730e6f76a1a4e539))
* **containers:** dim compose group header when all containers are stopped\n\nApply muted foreground colors to the layer icon and project name in\nContainerGroupView when no containers in the group are running. This\nmakes it visually consistent with stopped standalone container rows\nand easier to distinguish running groups from stopped ones at a glance. ([fa2f653](https://github.com/arcboxlabs/arcbox-desktop/commit/fa2f6537678687d4cc1d331877cd7e8d5221e00d))
* **containers:** refresh terminal when switching containers ([d79478d](https://github.com/arcboxlabs/arcbox-desktop/commit/d79478d57d3d769b02f53729d6103042171d2778))
* **containers:** show domain/ip/mounts reliably in info panel ([b236498](https://github.com/arcboxlabs/arcbox-desktop/commit/b23649821ae0b863301cc9742c9be10014a79ec2))
* correct daemon socket paths to match runtime directory ([bbc3fe7](https://github.com/arcboxlabs/arcbox-desktop/commit/bbc3fe74a5d3decce6461a5b34400d350beeace3))
* **daemon:** avoid blocking main thread in reachability check and add fast path ([6d5dd93](https://github.com/arcboxlabs/arcbox-desktop/commit/6d5dd93e3802cfbc391c66a85d1066598a87d4fa))
* **docker:** fix volumes and images decoding errors, add volume size support ([424ca65](https://github.com/arcboxlabs/arcbox-desktop/commit/424ca65f33d1af660cbaa27ad37bbdc9fed2bac9))
* **docker:** handle TTY container logs without multiplexed framing ([274595c](https://github.com/arcboxlabs/arcbox-desktop/commit/274595c80d4e1d9a6fd873692c40286e108d0ef5))
* force SMAppService re-registration to resolve stale bundle paths ([f96f9c2](https://github.com/arcboxlabs/arcbox-desktop/commit/f96f9c2a63b11edb4d68cd8a516874c12e0e4ec2))
* **icon:** add standard macOS drop shadow to app icon ([264e052](https://github.com/arcboxlabs/arcbox-desktop/commit/264e052af8998ef40f1ff8f1e99a4ba635969f2e))
* **icon:** apply macOS HIG padding and corner radius to app icon ([6232d5b](https://github.com/arcboxlabs/arcbox-desktop/commit/6232d5b2f4b438dd05cfdb0a36d8c85f0424c290))
* **images:** resolve terminal hang when switching images or tabs ([c7a351d](https://github.com/arcboxlabs/arcbox-desktop/commit/c7a351d6eea6c2505ff7dae36bc90a0c6927d7c1))
* **init:** reactively create Docker/gRPC clients on daemon state change ([88c8675](https://github.com/arcboxlabs/arcbox-desktop/commit/88c8675d8f54cd4228ae3e3ef18459b4aae55fff))
* **logs:** avoid log gap between history and streaming phases ([7945b44](https://github.com/arcboxlabs/arcbox-desktop/commit/7945b44dc3453764b81636d963724cfb713d6fc1))
* **logs:** convert UTC timestamps to user's local timezone ([0220962](https://github.com/arcboxlabs/arcbox-desktop/commit/0220962400d0a7dca367a8314c99d8295776828a))
* **logs:** fix stream cancellation and error handling ([14c4adc](https://github.com/arcboxlabs/arcbox-desktop/commit/14c4adc2e1bc6467669faaa2557b78adf9841ed9))
* make helper setup non-blocking to prevent startup hang ([f9b6023](https://github.com/arcboxlabs/arcbox-desktop/commit/f9b6023d03a98c4cf453fe69ef431386f581ce10))
* **models:** use distantPast fallback for unparseable dates ([72cca5c](https://github.com/arcboxlabs/arcbox-desktop/commit/72cca5c28fef2c11344ab738edd8859b1b6576d3))
* **packaging:** deep-sign bundle first then re-sign daemon with entitlements ([ddce0c7](https://github.com/arcboxlabs/arcbox-desktop/commit/ddce0c75e7e28daa61fbda324ceac49503ce5df0))
* **packaging:** embed boot-assets into app bundle ([143faa7](https://github.com/arcboxlabs/arcbox-desktop/commit/143faa758b949539968048dd9edb2b12889fe590))
* **packaging:** re-sign outer app after daemon entitlement to refresh seal ([bbdbc96](https://github.com/arcboxlabs/arcbox-desktop/commit/bbdbc96241428f7d54dd7632dd6a1a2a1fecd6aa))
* **packaging:** sign ArcBoxHelper and fetch notarization log on failure ([013952b](https://github.com/arcboxlabs/arcbox-desktop/commit/013952b558af2c1028a05a8c16697e70a9ca46a5))
* **packaging:** sign daemon helper with virtualization entitlement before app bundle ([345c6a1](https://github.com/arcboxlabs/arcbox-desktop/commit/345c6a1dca7ad70b397c5f5526bb303ae534335e))
* resolve ArcBoxHelper XPC daemon launch failures ([#12](https://github.com/arcboxlabs/arcbox-desktop/issues/12)) ([4623cdd](https://github.com/arcboxlabs/arcbox-desktop/commit/4623cdd9b10b8fbcba6474a4264d73964d71e6f7))
* **terminal:** make reconnect button actually reconnect ([199e1a3](https://github.com/arcboxlabs/arcbox-desktop/commit/199e1a3d41fffe19c1d5f0e20f433e8c213192e9))
* **terminal:** use setString for clipboard copy ([cbb944c](https://github.com/arcboxlabs/arcbox-desktop/commit/cbb944c22b04a618c37edec99352454876eaea73))
* trigger release workflow on release event from release-please ([ee414a0](https://github.com/arcboxlabs/arcbox-desktop/commit/ee414a00f7c70d1f834464f25c7addda8e579cf2))
* **ui:** allow resizable content column in NavigationSplitView ([72fb81d](https://github.com/arcboxlabs/arcbox-desktop/commit/72fb81d1519d4875145ef5a479fe71c158c695f7))
* **ui:** resolve merge conflict in ContainersListView and use shared environment ViewModel ([da1c61a](https://github.com/arcboxlabs/arcbox-desktop/commit/da1c61ac02da1b83cb369116935e3368d5afbe2f))
* **ui:** unify list row selection style and panel width ([2e8deeb](https://github.com/arcboxlabs/arcbox-desktop/commit/2e8deeb7340593d8876e14a067cc5f777cc12ed3))
* **ui:** use fixed column widths in NavigationSplitView ([3e33a37](https://github.com/arcboxlabs/arcbox-desktop/commit/3e33a379653fd8560198331fcbaff9155d605675))
* **ui:** use mount content for info tab refresh key ([a1cf86d](https://github.com/arcboxlabs/arcbox-desktop/commit/a1cf86d134784c5dab55f8ffd1384b340c08738a))

## [1.3.0](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.2.2...v1.3.0) (2026-03-13)


### Features

* add abctl CLI to build/sign pipeline and update dev team ([8b108c6](https://github.com/arcboxlabs/arcbox-desktop/commit/8b108c6c58a37271457af29b99553af1b166cc4a))
* add ArcBoxClient local Swift package for gRPC daemon communication ([5bf00d5](https://github.com/arcboxlabs/arcbox-desktop/commit/5bf00d597a3ea4e7eb17ef0a330c952b478a4ed0))
* add ArcBoxHelper privileged helper for root-level operations ([61f93f0](https://github.com/arcboxlabs/arcbox-desktop/commit/61f93f00812e1ade0f347dddf7eb403faf606322))
* add DockerClient package with swift-openapi-generator ([aa2e4c3](https://github.com/arcboxlabs/arcbox-desktop/commit/aa2e4c3a5e86868195936badc3af0c253cdb8a2d))
* add search filtering for containers, images, and volumes lists ([fb29852](https://github.com/arcboxlabs/arcbox-desktop/commit/fb2985295c7462d8a6d5dd667eb88d11a86572fe))
* add Unix socket transport and integrate Docker Engine API ([f2f86c3](https://github.com/arcboxlabs/arcbox-desktop/commit/f2f86c368adf4a97e95a84d9ff624f967e8b785f))
* **app:** auto-register CLI on first launch via `arcbox setup install` ([9d3b291](https://github.com/arcboxlabs/arcbox-desktop/commit/9d3b2913813a2e2d1f957824ca214cda9a1f3919))
* auto-install Docker CLI tools and enable context on app launch ([4561d69](https://github.com/arcboxlabs/arcbox-desktop/commit/4561d699e89f5b133d1502ab7e52b3b48ea1b5ce))
* **boot:** add BootAssetManager and integrate into app startup ([1ee0840](https://github.com/arcboxlabs/arcbox-desktop/commit/1ee08409a0a2a7420234bd622cfd46805746c366))
* bundle and seed arcbox-agent for daemon startup ([e027508](https://github.com/arcboxlabs/arcbox-desktop/commit/e027508c6ce2de6f35c5a787587bac50f687ea01))
* **ci:** add code signing and notarization to release workflow ([e6ae4ab](https://github.com/arcboxlabs/arcbox-desktop/commit/e6ae4ab11fbaf9b656eda67e416f5460cc5fe003))
* **ci:** add DMG release workflow ([cbd39d6](https://github.com/arcboxlabs/arcbox-desktop/commit/cbd39d673ac9f566ce9bad6415a542b9023570c6))
* **ci:** add release-please for automated version management ([3dadf72](https://github.com/arcboxlabs/arcbox-desktop/commit/3dadf72db95495b873b5075a176f8493a700957b))
* **ci:** pin arcbox version via arcbox.version file ([387d73d](https://github.com/arcboxlabs/arcbox-desktop/commit/387d73d799dc982bfa04405dd92924af6ed14b10))
* **cli:** update CLIRunner for abctl binary rename ([2e5e01a](https://github.com/arcboxlabs/arcbox-desktop/commit/2e5e01a06673c5abb7084646084aaabe01b39775))
* **containers:** implement local rootfs filesystem browser ([8be7bc8](https://github.com/arcboxlabs/arcbox-desktop/commit/8be7bc8ca6e3d05551f3b56cb7f29657396a6bdf))
* **containers:** implement real container logs with streaming support ([356790f](https://github.com/arcboxlabs/arcbox-desktop/commit/356790ffc61138d132e7028e96d0c65154714e72))
* **containers:** implement real interactive terminal with SwiftTerm ([9962bba](https://github.com/arcboxlabs/arcbox-desktop/commit/9962bba4857dfc1b25b72a1ae39e900ec91a9393))
* **containers:** improve list UI with loading states, sections, and group actions ([ebf306d](https://github.com/arcboxlabs/arcbox-desktop/commit/ebf306d6195b420ddd4e46b9fedb6daff838a366))
* **containers:** match compose group header height to container row\n\nIncrease ContainerGroupView header frame height from 36 to 44 so compose\ngroup cells align visually with standalone container rows in the list. ([9fc8669](https://github.com/arcboxlabs/arcbox-desktop/commit/9fc8669b4559c6ee56f3c0c95414e0a8dd347866))
* daemon lifecycle management via SMAppService ([da243aa](https://github.com/arcboxlabs/arcbox-desktop/commit/da243aa2b2287d3ce3235044e90f0a3c48c900f8))
* **delete:** wire up delete for images, volumes, and networks ([2acec3b](https://github.com/arcboxlabs/arcbox-desktop/commit/2acec3bf9c18bb5bde6ff5f8e0ab84693aaa5cd1))
* **dmg:** embed Docker tools, completions, and pstramp ([f9ff1fc](https://github.com/arcboxlabs/arcbox-desktop/commit/f9ff1fcb478f4033b523ca95a37042130bdb96b9))
* **events:** add real-time Docker events monitoring via DockerEventMonitor ([8c89d13](https://github.com/arcboxlabs/arcbox-desktop/commit/8c89d132833128818fe0ffa8a881075eb4a14d96))
* **images:** implement local rootfs filesystem browser for images ([bbb9553](https://github.com/arcboxlabs/arcbox-desktop/commit/bbb9553fc70e984778d1c63b356f9ea499e52335))
* **images:** implement real interactive terminal for images ([c3cd532](https://github.com/arcboxlabs/arcbox-desktop/commit/c3cd5322fd0d4ea8ca54b633e07d60f328ba9d07))
* integrate Sparkle auto-update framework ([#6](https://github.com/arcboxlabs/arcbox-desktop/issues/6)) ([df2d7a4](https://github.com/arcboxlabs/arcbox-desktop/commit/df2d7a4176d763bd1932d272898ea38224e030ec))
* **network:** add new button to create new network ([5e76b3b](https://github.com/arcboxlabs/arcbox-desktop/commit/5e76b3b65dcfafcd9e8184600fa019c268518161))
* **release:** add Backblaze B2 CDN distribution and Sparkle EdDSA signing ([e636df6](https://github.com/arcboxlabs/arcbox-desktop/commit/e636df6462f42e43d6db5bc630eb28a211e3c59e))
* **sparkle:** integrate Sparkle auto-update ([#7](https://github.com/arcboxlabs/arcbox-desktop/issues/7)) ([d66b954](https://github.com/arcboxlabs/arcbox-desktop/commit/d66b95498b81f3769847dbae8e3bc5c8b23c2921))
* stream Docker tool install progress via DockerToolSetupManager ([8244db8](https://github.com/arcboxlabs/arcbox-desktop/commit/8244db898bb5824371d979f632113a30f5eb0735))
* **ui:** add app icon assets ([06a195d](https://github.com/arcboxlabs/arcbox-desktop/commit/06a195d0402bc7c83a127e5e27d6ad468af1aa28))
* **ui:** add copy button and text selection to CommandHint ([a642cfd](https://github.com/arcboxlabs/arcbox-desktop/commit/a642cfd194b78567701ce63a723ef222f8795cbf))
* **ui:** add create dialogs for volumes, images, and networks ([3ed1ab7](https://github.com/arcboxlabs/arcbox-desktop/commit/3ed1ab73d428eba4e7e42fc83dfdd0e10be1bcf5))
* **ui:** add Kubernetes pods and services sections ([2448d64](https://github.com/arcboxlabs/arcbox-desktop/commit/2448d641a32022496d1b6cff5a1d3bce5995c27c))
* **ui:** add localhost link button and domain display for containers with ports ([22da16e](https://github.com/arcboxlabs/arcbox-desktop/commit/22da16efadbd119baee2fc965c503728eabcdc48))
* **ui:** add Sandbox section with Sandboxes and Templates ([5ea9092](https://github.com/arcboxlabs/arcbox-desktop/commit/5ea9092d307cd2975b86eafc515eca19037992c5))
* **ui:** add SwiftUI port of arcbox-desktop UI ([0ba79b1](https://github.com/arcboxlabs/arcbox-desktop/commit/0ba79b110c1eaf8bebd8da6f6c21ae27bd2d7a23))
* **ui:** add the zebra line and optimize the ui of filesystem browser ([3c4b5c9](https://github.com/arcboxlabs/arcbox-desktop/commit/3c4b5c99b13a639d0b0802e00d318f70e9625631))
* **ui:** flatten sort menu into single-level with sections ([a0c38c4](https://github.com/arcboxlabs/arcbox-desktop/commit/a0c38c4fd94ea7c882de42aa4612088e0bbb9090))
* **ui:** implement container detail tabs (Info, Logs, Terminal, Files) ([0129457](https://github.com/arcboxlabs/arcbox-desktop/commit/012945734cf53e18f14ba6bb2169f26e0846ac79))
* **ui:** implement detail tabs for volumes, images, and networks ([f97e7ef](https://github.com/arcboxlabs/arcbox-desktop/commit/f97e7ef34aac56bc3a4c6d1bebdbdc356a117327))
* **ui:** implement sort menu logic across all list views ([10c6f8a](https://github.com/arcboxlabs/arcbox-desktop/commit/10c6f8af193dd29b06f768626a7a738e42e9b0ad))
* **ui:** set menu bar app name to ArcBox Desktop ([a049605](https://github.com/arcboxlabs/arcbox-desktop/commit/a049605bff515a764830cf6bd9d0cb7a63d05f77))
* **ui:** show decimal precision for size display across volumes and images ([58d63ba](https://github.com/arcboxlabs/arcbox-desktop/commit/58d63bab4cd3419d4185abbd91585cf2cf9c28be))
* **ui:** show loading indicator during daemon startup and shutdown ([05b4549](https://github.com/arcboxlabs/arcbox-desktop/commit/05b45491629e695111cfc2dc765743bfb749e8b0))
* **volumes:** implement local rootfs filesystem browser for volumes ([d350189](https://github.com/arcboxlabs/arcbox-desktop/commit/d3501890df17e21c6160507a41303fe04f9d3afb))


### Bug Fixes

* add missing await on SMAppService.unregister() in teardown path ([17176e4](https://github.com/arcboxlabs/arcbox-desktop/commit/17176e47992ac82294c235c0396a85dc5d80368a))
* bundle all runtime binaries in DMG via abctl boot prefetch ([8754160](https://github.com/arcboxlabs/arcbox-desktop/commit/8754160efb6081f9bafb979eca92f7b4b895f8ba))
* **ci:** add package-dmg.sh and fix workflow references ([ebb6b18](https://github.com/arcboxlabs/arcbox-desktop/commit/ebb6b182e4fee7fb718dfb7549f9f0bc956238ce))
* **ci:** auto-download latest arcbox release when ref is not a tag ([8fb77c5](https://github.com/arcboxlabs/arcbox-desktop/commit/8fb77c5d881b871d378d3c08b700d7ad2caff102))
* **ci:** create empty Local.xcconfig for CI builds ([a2e0408](https://github.com/arcboxlabs/arcbox-desktop/commit/a2e0408422ebd6e358123699c92aa3dd091c6c8a))
* **ci:** create release as draft until DMG is attached ([81e6077](https://github.com/arcboxlabs/arcbox-desktop/commit/81e607756fd8f90a426150a1d9ee27af3cf50afe))
* **ci:** extract tarball before searching for arcbox binaries ([175cf21](https://github.com/arcboxlabs/arcbox-desktop/commit/175cf21507d9be026b4a32b8b9f2fba878ce218c))
* **ci:** improve Sparkle signing error visibility and use vars for public key ([fff55ee](https://github.com/arcboxlabs/arcbox-desktop/commit/fff55ee64e0436faee2964b53785db7b8b8dacd9))
* **ci:** remove unnecessary token for public arcbox repo checkout ([cc4196e](https://github.com/arcboxlabs/arcbox-desktop/commit/cc4196e17464ba13805830657b67e53f54265a89))
* **ci:** rename arcbox checkout path to avoid case-insensitive FS collision ([8d92555](https://github.com/arcboxlabs/arcbox-desktop/commit/8d925554175b25a2ea9ddc7cf78b95084741f4f1))
* **ci:** resolve SPM package name collision and shallow clone build number ([f03ea69](https://github.com/arcboxlabs/arcbox-desktop/commit/f03ea69a7694baafd1392ee27b617ee092e6f6b2))
* **ci:** revert SPARKLE_PUBLIC_KEY back to secrets ([a632971](https://github.com/arcboxlabs/arcbox-desktop/commit/a63297116684e06d7483b326a775d4272aa5db60))
* **ci:** skip Rust build when pre-built binaries are available ([c9e5163](https://github.com/arcboxlabs/arcbox-desktop/commit/c9e516389c92f7f44c8f5e998f737cc9cbb645f6))
* **ci:** skip SwiftPM plugin validation for OpenAPIGenerator ([#4](https://github.com/arcboxlabs/arcbox-desktop/issues/4)) ([3b9b0cf](https://github.com/arcboxlabs/arcbox-desktop/commit/3b9b0cf2e637bb8c873d269df9cf26417906f4bd))
* **ci:** symlink arcbox for Xcode build phase script ([a03fb7d](https://github.com/arcboxlabs/arcbox-desktop/commit/a03fb7d4a266ede23f4cfcb213f6b0d6bd6884cd))
* **ci:** use printf instead of echo for Sparkle private key to avoid trailing newline ([52f7d97](https://github.com/arcboxlabs/arcbox-desktop/commit/52f7d970f71427254df0a404d06d841dd543f4fc))
* **ci:** use Xcode global default to skip plugin validation ([8059c2c](https://github.com/arcboxlabs/arcbox-desktop/commit/8059c2c3eb0b96b3591cd7111082977e70e04f67))
* **client:** move all Process/IO off MainActor to prevent UI freezes ([bf42a45](https://github.com/arcboxlabs/arcbox-desktop/commit/bf42a458995d08c8e0ff74cdf3c99d258cccbcf7))
* **containers:** align ArcBox rootfs and socket resolution ([e552dfe](https://github.com/arcboxlabs/arcbox-desktop/commit/e552dfedd8c72e2f7f54c531730e6f76a1a4e539))
* **containers:** dim compose group header when all containers are stopped\n\nApply muted foreground colors to the layer icon and project name in\nContainerGroupView when no containers in the group are running. This\nmakes it visually consistent with stopped standalone container rows\nand easier to distinguish running groups from stopped ones at a glance. ([fa2f653](https://github.com/arcboxlabs/arcbox-desktop/commit/fa2f6537678687d4cc1d331877cd7e8d5221e00d))
* **containers:** refresh terminal when switching containers ([d79478d](https://github.com/arcboxlabs/arcbox-desktop/commit/d79478d57d3d769b02f53729d6103042171d2778))
* **containers:** show domain/ip/mounts reliably in info panel ([b236498](https://github.com/arcboxlabs/arcbox-desktop/commit/b23649821ae0b863301cc9742c9be10014a79ec2))
* correct daemon socket paths to match runtime directory ([bbc3fe7](https://github.com/arcboxlabs/arcbox-desktop/commit/bbc3fe74a5d3decce6461a5b34400d350beeace3))
* **daemon:** avoid blocking main thread in reachability check and add fast path ([6d5dd93](https://github.com/arcboxlabs/arcbox-desktop/commit/6d5dd93e3802cfbc391c66a85d1066598a87d4fa))
* **docker:** fix volumes and images decoding errors, add volume size support ([424ca65](https://github.com/arcboxlabs/arcbox-desktop/commit/424ca65f33d1af660cbaa27ad37bbdc9fed2bac9))
* **docker:** handle TTY container logs without multiplexed framing ([274595c](https://github.com/arcboxlabs/arcbox-desktop/commit/274595c80d4e1d9a6fd873692c40286e108d0ef5))
* force SMAppService re-registration to resolve stale bundle paths ([f96f9c2](https://github.com/arcboxlabs/arcbox-desktop/commit/f96f9c2a63b11edb4d68cd8a516874c12e0e4ec2))
* **icon:** add standard macOS drop shadow to app icon ([264e052](https://github.com/arcboxlabs/arcbox-desktop/commit/264e052af8998ef40f1ff8f1e99a4ba635969f2e))
* **icon:** apply macOS HIG padding and corner radius to app icon ([6232d5b](https://github.com/arcboxlabs/arcbox-desktop/commit/6232d5b2f4b438dd05cfdb0a36d8c85f0424c290))
* **images:** resolve terminal hang when switching images or tabs ([c7a351d](https://github.com/arcboxlabs/arcbox-desktop/commit/c7a351d6eea6c2505ff7dae36bc90a0c6927d7c1))
* **init:** reactively create Docker/gRPC clients on daemon state change ([88c8675](https://github.com/arcboxlabs/arcbox-desktop/commit/88c8675d8f54cd4228ae3e3ef18459b4aae55fff))
* **logs:** avoid log gap between history and streaming phases ([7945b44](https://github.com/arcboxlabs/arcbox-desktop/commit/7945b44dc3453764b81636d963724cfb713d6fc1))
* **logs:** convert UTC timestamps to user's local timezone ([0220962](https://github.com/arcboxlabs/arcbox-desktop/commit/0220962400d0a7dca367a8314c99d8295776828a))
* **logs:** fix stream cancellation and error handling ([14c4adc](https://github.com/arcboxlabs/arcbox-desktop/commit/14c4adc2e1bc6467669faaa2557b78adf9841ed9))
* make helper setup non-blocking to prevent startup hang ([f9b6023](https://github.com/arcboxlabs/arcbox-desktop/commit/f9b6023d03a98c4cf453fe69ef431386f581ce10))
* **models:** use distantPast fallback for unparseable dates ([72cca5c](https://github.com/arcboxlabs/arcbox-desktop/commit/72cca5c28fef2c11344ab738edd8859b1b6576d3))
* **packaging:** deep-sign bundle first then re-sign daemon with entitlements ([ddce0c7](https://github.com/arcboxlabs/arcbox-desktop/commit/ddce0c75e7e28daa61fbda324ceac49503ce5df0))
* **packaging:** embed boot-assets into app bundle ([143faa7](https://github.com/arcboxlabs/arcbox-desktop/commit/143faa758b949539968048dd9edb2b12889fe590))
* **packaging:** re-sign outer app after daemon entitlement to refresh seal ([bbdbc96](https://github.com/arcboxlabs/arcbox-desktop/commit/bbdbc96241428f7d54dd7632dd6a1a2a1fecd6aa))
* **packaging:** sign ArcBoxHelper and fetch notarization log on failure ([013952b](https://github.com/arcboxlabs/arcbox-desktop/commit/013952b558af2c1028a05a8c16697e70a9ca46a5))
* **packaging:** sign daemon helper with virtualization entitlement before app bundle ([345c6a1](https://github.com/arcboxlabs/arcbox-desktop/commit/345c6a1dca7ad70b397c5f5526bb303ae534335e))
* resolve ArcBoxHelper XPC daemon launch failures ([#12](https://github.com/arcboxlabs/arcbox-desktop/issues/12)) ([4623cdd](https://github.com/arcboxlabs/arcbox-desktop/commit/4623cdd9b10b8fbcba6474a4264d73964d71e6f7))
* **terminal:** make reconnect button actually reconnect ([199e1a3](https://github.com/arcboxlabs/arcbox-desktop/commit/199e1a3d41fffe19c1d5f0e20f433e8c213192e9))
* **terminal:** use setString for clipboard copy ([cbb944c](https://github.com/arcboxlabs/arcbox-desktop/commit/cbb944c22b04a618c37edec99352454876eaea73))
* trigger release workflow on release event from release-please ([ee414a0](https://github.com/arcboxlabs/arcbox-desktop/commit/ee414a00f7c70d1f834464f25c7addda8e579cf2))
* **ui:** allow resizable content column in NavigationSplitView ([72fb81d](https://github.com/arcboxlabs/arcbox-desktop/commit/72fb81d1519d4875145ef5a479fe71c158c695f7))
* **ui:** resolve merge conflict in ContainersListView and use shared environment ViewModel ([da1c61a](https://github.com/arcboxlabs/arcbox-desktop/commit/da1c61ac02da1b83cb369116935e3368d5afbe2f))
* **ui:** unify list row selection style and panel width ([2e8deeb](https://github.com/arcboxlabs/arcbox-desktop/commit/2e8deeb7340593d8876e14a067cc5f777cc12ed3))
* **ui:** use fixed column widths in NavigationSplitView ([3e33a37](https://github.com/arcboxlabs/arcbox-desktop/commit/3e33a379653fd8560198331fcbaff9155d605675))
* **ui:** use mount content for info tab refresh key ([a1cf86d](https://github.com/arcboxlabs/arcbox-desktop/commit/a1cf86d134784c5dab55f8ffd1384b340c08738a))

## [1.2.2](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.2.1...v1.2.2) (2026-03-13)


### Bug Fixes

* bundle all runtime binaries in DMG via abctl boot prefetch ([8754160](https://github.com/arcboxlabs/arcbox-desktop/commit/8754160efb6081f9bafb979eca92f7b4b895f8ba))
* **ci:** create release as draft until DMG is attached ([81e6077](https://github.com/arcboxlabs/arcbox-desktop/commit/81e607756fd8f90a426150a1d9ee27af3cf50afe))

## [1.2.1](https://github.com/arcboxlabs/arcbox-desktop/compare/v1.2.0...v1.2.1) (2026-03-13)


### Bug Fixes

* **icon:** add standard macOS drop shadow to app icon ([264e052](https://github.com/arcboxlabs/arcbox-desktop/commit/264e052af8998ef40f1ff8f1e99a4ba635969f2e))

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
