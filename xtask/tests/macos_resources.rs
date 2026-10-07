#![cfg(target_os = "macos")]

use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::Command;

fn prepare_resources(runtime: &Path, command_log: &Path) -> Command {
    let boot_version = runtime.parent().unwrap().file_name().unwrap();
    std::fs::create_dir_all(runtime).unwrap();
    std::fs::write(
        runtime.join("assets.lock"),
        format!("[boot]\nversion = \"{}\"\n", boot_version.to_string_lossy()),
    )
    .unwrap();

    let mut command = Command::new(env!("CARGO_BIN_EXE_xtask"));
    command
        .args(["macos", "prepare-resources", "--dev", "--arcbox-dir"])
        .arg(runtime)
        .env("ARCBOX_TEST_COMMAND_LOG", command_log)
        .env_remove("BOOT_ASSETS_DIR")
        .env_remove("BOOT_ASSETS_KERNEL")
        .env_remove("BOOT_ASSETS_ROOTFS");
    command
}

fn install_fake_abctl(host_dir: &Path) {
    std::fs::create_dir_all(host_dir).unwrap();
    let abctl = host_dir.join("abctl");
    std::fs::write(
        &abctl,
        "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$ARCBOX_TEST_COMMAND_LOG\"\n",
    )
    .unwrap();
    std::fs::set_permissions(abctl, std::fs::Permissions::from_mode(0o755)).unwrap();
}

#[test]
fn resource_preparation_uses_configured_host_binaries() {
    let dir = tempfile::tempdir().unwrap();
    let runtime = dir.path().join("runtime");
    let host_dir = dir.path().join("host-binaries");
    let command_log = dir.path().join("commands");
    install_fake_abctl(&host_dir);

    let output = prepare_resources(&runtime, &command_log)
        .env("ARCBOX_HOST_BIN_DIR", &host_dir)
        .output()
        .unwrap();

    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        std::fs::read_to_string(command_log).unwrap(),
        "--profile development boot prefetch\n--profile development docker setup\n"
    );
}

#[test]
fn invalid_host_directory_does_not_use_legacy_binaries() {
    let dir = tempfile::tempdir().unwrap();
    let runtime = dir.path().join("runtime");
    let missing_host_dir = dir.path().join("missing-host-binaries");
    let command_log = dir.path().join("commands");
    install_fake_abctl(&runtime.join("target/release"));

    let output = prepare_resources(&runtime, &command_log)
        .env("ARCBOX_HOST_BIN_DIR", &missing_host_dir)
        .output()
        .unwrap();

    assert!(!output.status.success());
    let error = String::from_utf8_lossy(&output.stderr);
    assert!(
        error.contains(missing_host_dir.to_str().unwrap()),
        "{error}"
    );
    assert!(!command_log.exists());
}
