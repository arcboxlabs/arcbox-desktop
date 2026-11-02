use std::collections::BTreeSet;

use serde_json::json;

use super::{
    cargo_about_licenses, check_coverage, classify_license, collect_swift_packages, shipped_keys,
};

const ASSETS_LOCK: &str = r#"
[boot]
version = "0.8.11"
cdn = "https://boot.arcboxcdn.com"

[[tools]]
name = "docker"
group = "docker"
version = "29.9.2"
arch.arm64.sha256 = "aaa"

[[tools]]
name = "pstramp"
group = "desktop"
version = "0.2.0"
arch.arm64.sha256 = "bbb"

[[tools]]
name = "kubectl"
group = "kubernetes"
version = "1.37.1"
arch.arm64.sha256 = "ccc"
"#;

fn keys(keys: &[&str]) -> BTreeSet<String> {
    keys.iter().map(|key| (*key).to_owned()).collect()
}

#[test]
fn shipped_keys_name_every_tool_boot_assets_and_host_runtime_binaries() {
    let manifest = json!({
        "asset_version": "0.8.11",
        "targets": {
            "arm64": { "kernel": { "version": "v0.0.25" } },
            "x86_64": { "kernel": { "version": "v0.0.24" } },
        },
        "binaries": [
            { "name": "dockerd", "version": "29.9.2", "targets": { "arm64": {}, "x86_64": {} } },
            { "name": "FEX", "version": "FEX-2605-0.8.11", "targets": { "arm64": {} } },
            { "name": "x86-only", "version": "1.0", "targets": { "x86_64": {} } },
        ],
    });

    assert_eq!(
        shipped_keys(ASSETS_LOCK, &manifest).unwrap(),
        keys(&[
            "boot:kernel@v0.0.25",
            "boot:rootfs@0.8.11",
            "runtime:FEX@FEX-2605-0.8.11",
            "runtime:dockerd@29.9.2",
            "tool:docker@29.9.2",
            "tool:kubectl@1.37.1",
            "tool:pstramp@0.2.0",
        ])
    );
}

#[test]
fn coverage_must_match_the_shipped_versions_both_ways() {
    let shipped = keys(&["runtime:dockerd@29.9.3", "boot:rootfs@0.8.11"]);
    assert!(check_coverage(&shipped, &shipped).is_ok());

    let error = check_coverage(
        &shipped,
        &keys(&["runtime:dockerd@29.9.2", "boot:rootfs@0.8.11"]),
    )
    .unwrap_err()
    .to_string();
    assert!(
        error.contains("shipped but not covered: runtime:dockerd@29.9.3"),
        "{error}"
    );
    assert!(
        error.contains("covered but not shipped: runtime:dockerd@29.9.2"),
        "{error}"
    );
}

#[test]
fn swift_package_notices_copy_license_before_notice() {
    let dir = tempfile::tempdir().unwrap();
    let checkouts = dir.path().join("checkouts");
    let nio = checkouts.join("swift-nio");
    std::fs::create_dir_all(nio.join("Sources")).unwrap();
    std::fs::write(nio.join("NOTICE.txt"), "The SwiftNIO Project").unwrap();
    std::fs::write(
        nio.join("LICENSE.txt"),
        "Apache License\nVersion 2.0, January 2004",
    )
    .unwrap();
    std::fs::write(nio.join("README.md"), "readme").unwrap();
    let notices = dir.path().join("ThirdPartyNotices");
    let resolved = json!({ "pins": [{
        "identity": "swift-nio",
        "location": "https://github.com/apple/swift-nio.git",
        "state": { "revision": "abc", "version": "2.95.0" },
    }]});

    let packages = collect_swift_packages(&resolved, &checkouts, &notices).unwrap();

    assert_eq!(
        packages,
        vec![json!({
            "name": "swift-nio",
            "version": "2.95.0",
            "license": "Apache-2.0",
            "source": "https://github.com/apple/swift-nio",
            "licenseFiles": [
                "swift-packages/swift-nio/LICENSE.txt",
                "swift-packages/swift-nio/NOTICE.txt",
            ],
        })]
    );
    assert_eq!(
        std::fs::read_to_string(notices.join("swift-packages/swift-nio/NOTICE.txt")).unwrap(),
        "The SwiftNIO Project"
    );
}

#[test]
fn swift_package_without_a_license_file_fails_packaging() {
    let dir = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(dir.path().join("checkouts/Yams")).unwrap();
    let resolved = json!({ "pins": [{
        "identity": "yams",
        "location": "https://github.com/jpsim/Yams",
        "state": { "version": "6.2.2" },
    }]});

    let error = collect_swift_packages(&resolved, &dir.path().join("checkouts"), dir.path())
        .unwrap_err()
        .to_string();

    assert!(
        error.contains("Swift package yams has no LICENSE"),
        "{error}"
    );
}

#[test]
fn license_label_follows_the_license_the_file_opens_with() {
    let plcrashreporter = "\
Permission is hereby granted, free of charge, to any person obtaining a copy
...
Some sources are Licensed under the Apache License, Version 2.0.";
    assert_eq!(classify_license(plcrashreporter), "MIT");
    assert_eq!(
        classify_license("Redistribution and use in source and binary forms ... Neither the name"),
        "BSD-3-Clause"
    );
    assert_eq!(classify_license("All rights reserved."), "See license text");
}

#[test]
fn cargo_about_licenses_come_from_the_overview_only() {
    let notice = "\
## Overview

- [MIT License](#MIT) (627 crates)
- [Mozilla Public License 2.0](#MPL-2.0) (5 crates)

---

## License Texts

### MIT License

Used by:
- [serde 1.0.228](https://github.com/serde-rs/serde)
- [Fake](#not-a-license)
";

    assert_eq!(cargo_about_licenses(notice), vec!["MIT", "MPL-2.0"]);
}
