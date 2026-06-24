use anyhow::Result;

use crate::MacosArgs;

#[cfg(target_os = "macos")]
pub mod bundle;
#[cfg(target_os = "macos")]
pub mod dmg;
#[cfg(target_os = "macos")]
pub mod embed;

#[cfg(target_os = "macos")]
pub fn run(args: MacosArgs) -> Result<()> {
    use crate::MacosCommand;

    match args.command {
        MacosCommand::Embed(args) => embed::run(args),
        MacosCommand::Bundle(args) => bundle::run(args),
        MacosCommand::Dmg(args) => dmg::run(args),
    }
}

#[cfg(not(target_os = "macos"))]
pub fn run(_args: MacosArgs) -> Result<()> {
    anyhow::bail!("`macos` commands are only available on macOS")
}
