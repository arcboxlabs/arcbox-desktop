//! Update (or create) the latest.json channel manifest used by Sparkle.
//!
//! Ported from the former `update-latest-json.py`; delegates to
//! `xtask_kit::latest_json::update`, which merges the existing channels,
//! upserts this channel with an ISO 8601 UTC timestamp, and pretty-prints with
//! sorted keys (matching the Python output).

use anyhow::Result;
use xtask_kit::latest_json::{self, UpdateOptions};

use crate::ReleaseLatestJsonArgs;

pub fn run(args: ReleaseLatestJsonArgs) -> Result<()> {
    let options = UpdateOptions {
        version: args.version,
        channel: args.channel,
        output: args.output,
        existing: args.existing,
    };
    latest_json::update(&options)
}
