#[cfg(target_os = "macos")]
use std::path::{Path, PathBuf};

use anyhow::Result;

use crate::MacosArgs;

#[cfg(target_os = "macos")]
pub(super) const ABCTL_CODE_SIGN_IDENTIFIER: &str = "com.arcboxlabs.desktop.cli";
#[cfg(target_os = "macos")]
pub(super) const HELPER_CODE_SIGN_IDENTIFIER: &str = "com.arcboxlabs.desktop.helper";

#[cfg(target_os = "macos")]
pub mod bundle;
#[cfg(target_os = "macos")]
pub mod dmg;
#[cfg(target_os = "macos")]
pub mod embed;

#[cfg(target_os = "macos")]
fn host_binary_dir(arcbox_dir: &Path) -> PathBuf {
    std::env::var_os("ARCBOX_HOST_BIN_DIR")
        .filter(|dir| !dir.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| arcbox_dir.join("target").join("release"))
}

#[cfg(target_os = "macos")]
pub fn run(args: MacosArgs) -> Result<()> {
    use crate::MacosCommand;

    match args.command {
        MacosCommand::Embed(args) => embed::run(args),
        MacosCommand::StageResources(args) => dmg::stage_resources_command(args),
        MacosCommand::Bundle(args) => bundle::run(args),
        MacosCommand::PrepareResources(args) => dmg::prepare_resources_command(args),
        MacosCommand::Dmg(args) => dmg::run(args),
    }
}

#[cfg(not(target_os = "macos"))]
pub fn run(_args: MacosArgs) -> Result<()> {
    anyhow::bail!("`macos` commands are only available on macOS")
}
