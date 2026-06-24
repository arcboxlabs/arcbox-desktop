pub mod appcast;
pub mod latest_json;
pub mod resolve;

use anyhow::Result;

use crate::{ReleaseArgs, ReleaseCommand};

pub fn run(args: ReleaseArgs) -> Result<()> {
    match args.command {
        ReleaseCommand::Resolve(args) => resolve::run(args),
        ReleaseCommand::Appcast(args) => appcast::run(args),
        ReleaseCommand::LatestJson(args) => latest_json::run(args),
    }
}
