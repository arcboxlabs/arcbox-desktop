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

/// ELF magic (`0x7f E L F`).
const ELF_MAGIC: [u8; 4] = [0x7f, b'E', b'L', b'F'];

/// Read the first four bytes of `path`, or `None` if unreadable / too short.
fn read_magic(path: &Path) -> Option<[u8; 4]> {
    if !path.is_file() {
        return None;
    }
    let mut file = File::open(path).ok()?;
    let mut magic = [0u8; 4];
    file.read_exact(&mut magic).ok()?;
    Some(magic)
}

/// Return `true` when `path` is a regular file whose first four bytes are a
/// Mach-O magic number. Mirrors the Python `is_macho` check.
pub fn is_macho(path: &Path) -> bool {
    read_magic(path).is_some_and(|m| MACHO_MAGICS.contains(&m))
}

/// Return `true` when `path` is a regular file with an ELF header.
pub fn is_elf(path: &Path) -> bool {
    read_magic(path).is_some_and(|m| m == ELF_MAGIC)
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    fn write_magic(dir: &tempfile::TempDir, name: &str, magic: &[u8; 4]) -> std::path::PathBuf {
        let path = dir.path().join(name);
        let mut f = std::fs::File::create(&path).unwrap();
        f.write_all(magic).unwrap();
        f.write_all(&[0u8; 12]).unwrap();
        path
    }

    #[test]
    fn detects_macho_and_elf_magics() {
        let dir = tempfile::tempdir().unwrap();
        let macho = write_magic(&dir, "macho", &[0xcf, 0xfa, 0xed, 0xfe]);
        let elf = write_magic(&dir, "elf", &[0x7f, b'E', b'L', b'F']);
        let other = write_magic(&dir, "txt", b"not!");

        assert!(is_macho(&macho));
        assert!(!is_elf(&macho));
        assert!(is_elf(&elf));
        assert!(!is_macho(&elf));
        assert!(!is_macho(&other));
        assert!(!is_elf(&other));
    }
}
