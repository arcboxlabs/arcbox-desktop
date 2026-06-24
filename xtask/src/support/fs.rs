//! Filesystem helpers reused by the macOS embed/dmg commands.

use std::fs::File;
use std::io::Read;
use std::path::Path;

use anyhow::{Context, Result};
use walkdir::WalkDir;

/// Recursively copy a directory tree, preserving symlinks (like Python's
/// `shutil.copytree(symlinks=True)`). Used to stage the built `.app` bundle,
/// whose `Frameworks/` contains relative symlinks.
pub fn copy_tree(src: &Path, dst: &Path) -> Result<()> {
    for entry in WalkDir::new(src).follow_links(false) {
        let entry = entry.with_context(|| format!("walking {}", src.display()))?;
        let rel = entry
            .path()
            .strip_prefix(src)
            .expect("walkdir entry is under src");
        let target = dst.join(rel);
        let file_type = entry.file_type();

        if file_type.is_symlink() {
            let link = std::fs::read_link(entry.path())
                .with_context(|| format!("readlink {}", entry.path().display()))?;
            if let Some(parent) = target.parent() {
                std::fs::create_dir_all(parent)
                    .with_context(|| format!("creating {}", parent.display()))?;
            }
            // Replace any stale entry, then recreate the symlink verbatim.
            let _ = std::fs::remove_file(&target);
            std::os::unix::fs::symlink(&link, &target)
                .with_context(|| format!("symlink {}", target.display()))?;
        } else if file_type.is_dir() {
            std::fs::create_dir_all(&target)
                .with_context(|| format!("creating {}", target.display()))?;
        } else {
            if let Some(parent) = target.parent() {
                std::fs::create_dir_all(parent)
                    .with_context(|| format!("creating {}", parent.display()))?;
            }
            std::fs::copy(entry.path(), &target).with_context(|| {
                format!("copying {} -> {}", entry.path().display(), target.display())
            })?;
        }
    }
    Ok(())
}

/// Mach-O magic numbers (little/big endian, 32/64-bit, and fat).
const MACHO_MAGICS: [[u8; 4]; 4] = [
    [0xcf, 0xfa, 0xed, 0xfe], // MH_MAGIC_64 (LE)
    [0xca, 0xfe, 0xba, 0xbe], // FAT_MAGIC
    [0xfe, 0xed, 0xfa, 0xcf], // MH_MAGIC_64 (BE)
    [0xce, 0xfa, 0xed, 0xfe], // MH_MAGIC (LE)
];

/// Return `true` when `path` is a regular file whose first four bytes are a
/// Mach-O magic number. Mirrors the Python `is_macho` check.
pub fn is_macho(path: &Path) -> bool {
    if !path.is_file() {
        return false;
    }
    let Ok(mut file) = File::open(path) else {
        return false;
    };
    let mut magic = [0u8; 4];
    if file.read_exact(&mut magic).is_err() {
        return false;
    }
    MACHO_MAGICS.contains(&magic)
}

/// Return `true` when `dst` is missing or its contents differ from `src`.
///
/// Equivalent to the Python `sync_binary` decision built on
/// `filecmp.cmp(shallow=False)`: a byte-for-byte content comparison.
pub fn needs_copy(src: &Path, dst: &Path) -> Result<bool> {
    if !dst.is_file() {
        return Ok(true);
    }
    let src_meta = std::fs::metadata(src).with_context(|| format!("stat {}", src.display()))?;
    let dst_meta = std::fs::metadata(dst).with_context(|| format!("stat {}", dst.display()))?;
    if src_meta.len() != dst_meta.len() {
        return Ok(true);
    }
    let src_bytes = std::fs::read(src).with_context(|| format!("read {}", src.display()))?;
    let dst_bytes = std::fs::read(dst).with_context(|| format!("read {}", dst.display()))?;
    Ok(src_bytes != dst_bytes)
}
