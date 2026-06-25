//! ArcBox protocol client generation tasks.

use std::ffi::OsStr;
use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{Context, Result, bail};
use tempfile::TempDir;
use xtask_kit::repo;

use crate::{ProtocolArgs, ProtocolCommand, ProtocolVerifyArgs};

pub fn run(args: ProtocolArgs) -> Result<()> {
    match args.command {
        ProtocolCommand::Bump(args) => bump(&args.version),
        ProtocolCommand::Verify(args) => verify(args),
    }
}

fn bump(version: &str) -> Result<()> {
    let root = repo_root()?;
    let snapshot = ProtocolSnapshot::capture(&root)?;
    std::fs::write(root.join("arcbox.version"), format!("{version}\n"))
        .context("writing arcbox.version")?;

    if let Err(error) = run_generate(&root) {
        snapshot.restore(&root)?;
        bail!("protobuf generation failed; restored arcbox.version and Generated/: {error:#}");
    }

    Ok(())
}

fn verify(_args: ProtocolVerifyArgs) -> Result<()> {
    let root = repo_root()?;
    run_generate(&root)?;

    let generated = "Packages/ArcBoxClient/Sources/ArcBoxClient/Generated/";
    if !run_status(&root, "git", ["diff", "--exit-code", generated])? {
        bail!(
            "Protobuf generated Swift files are out of date. Run: cargo xtask protocol bump --version {}",
            current_arcbox_version(&root)?
        );
    }

    let output = Command::new("git")
        .current_dir(&root)
        .args(["ls-files", "--others", "--exclude-standard", generated])
        .output()
        .context("running git ls-files")?;
    if !output.status.success() {
        bail!("git ls-files failed with status {}", output.status);
    }
    if !output.stdout.is_empty() {
        eprint!("{}", String::from_utf8_lossy(&output.stdout));
        bail!(
            "Untracked generated protobuf files detected. Run: cargo xtask protocol bump --version {}",
            current_arcbox_version(&root)?
        );
    }

    Ok(())
}

fn repo_root() -> Result<PathBuf> {
    repo::root_from_xtask_manifest(env!("CARGO_MANIFEST_DIR"))
}

fn current_arcbox_version(root: &Path) -> Result<String> {
    let version = std::fs::read_to_string(root.join("arcbox.version"))
        .context("reading arcbox.version")?
        .split_whitespace()
        .collect::<String>();
    Ok(version)
}

fn run_generate(root: &Path) -> Result<()> {
    let status = Command::new("./generate.sh")
        .arg("--remote")
        .current_dir(root.join("Packages/ArcBoxClient"))
        .status()
        .context("running Packages/ArcBoxClient/generate.sh --remote")?;

    if !status.success() {
        bail!("generate.sh failed with status {status}");
    }
    Ok(())
}

fn run_status<const N: usize>(root: &Path, program: &str, args: [&str; N]) -> Result<bool> {
    let status = Command::new(program)
        .current_dir(root)
        .args(args)
        .status()
        .with_context(|| format!("running {program}"))?;
    Ok(status.success())
}

struct ProtocolSnapshot {
    temp_dir: TempDir,
    arcbox_version: Option<String>,
}

impl ProtocolSnapshot {
    fn capture(root: &Path) -> Result<Self> {
        let temp_dir = tempfile::tempdir().context("creating protocol snapshot directory")?;
        let generated = generated_dir(root);
        let snapshot_generated = temp_dir.path().join("Generated");

        if generated.exists() {
            copy_dir_files(&generated, &snapshot_generated)?;
        }

        let arcbox_version = std::fs::read_to_string(root.join("arcbox.version")).ok();
        Ok(Self {
            temp_dir,
            arcbox_version,
        })
    }

    fn restore(&self, root: &Path) -> Result<()> {
        match &self.arcbox_version {
            Some(version) => std::fs::write(root.join("arcbox.version"), version)
                .context("restoring arcbox.version")?,
            None => match std::fs::remove_file(root.join("arcbox.version")) {
                Ok(()) => {}
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                Err(error) => return Err(error).context("removing arcbox.version"),
            },
        }

        let generated = generated_dir(root);
        if generated.exists() {
            std::fs::remove_dir_all(&generated)
                .with_context(|| format!("removing {}", generated.display()))?;
        }
        let snapshot_generated = self.temp_dir.path().join("Generated");
        if snapshot_generated.exists() {
            copy_dir_files(&snapshot_generated, &generated)?;
        } else {
            std::fs::create_dir_all(&generated)
                .with_context(|| format!("creating {}", generated.display()))?;
        }

        Ok(())
    }
}

fn generated_dir(root: &Path) -> PathBuf {
    root.join("Packages/ArcBoxClient/Sources/ArcBoxClient/Generated")
}

fn copy_dir_files(src: &Path, dst: &Path) -> Result<()> {
    std::fs::create_dir_all(dst).with_context(|| format!("creating {}", dst.display()))?;
    for entry in std::fs::read_dir(src).with_context(|| format!("reading {}", src.display()))? {
        let entry = entry.with_context(|| format!("reading entry under {}", src.display()))?;
        let path = entry.path();
        let target = dst.join(entry.file_name());
        if path.is_dir() {
            copy_dir_files(&path, &target)?;
        } else if path.extension() == Some(OsStr::new("swift")) {
            std::fs::copy(&path, &target)
                .with_context(|| format!("copying {} -> {}", path.display(), target.display()))?;
        }
    }
    Ok(())
}
