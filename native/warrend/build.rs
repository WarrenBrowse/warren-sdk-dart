//! Build-time coherence guard for the local WarrenGuard sibling.
//!
//! Cargo.toml consumes `warren-sdk` by a pinned git tag, but its
//! `[patch."...warrenguard.git"]` block repoints every engine crate to the LOCAL
//! sibling `../../../warrenguard`, which follows whatever rev is checked out
//! there (it is NOT pinned). A divergent or older sibling would silently compile
//! the SDK against a mismatched protocol engine: best case a confusing break,
//! worst case a clean build that speaks the wrong protocol and cannot reach the
//! live fleet. This guard asserts the engine rev the pinned tag expects (recorded
//! in `.warrenguard-expected-rev`) is an ancestor of the sibling's HEAD, and
//! fails loudly otherwise. It skips (warn only) when there is no local sibling
//! git checkout or no git, so a future build from a published crate without the
//! local patch is unaffected.

use std::path::Path;
use std::process::Command;

const EXPECTED_REV_FILE: &str = ".warrenguard-expected-rev";
const SIBLING_DIR: &str = "../../../warrenguard";

fn main() {
    println!("cargo:rerun-if-changed={EXPECTED_REV_FILE}");

    let expected_rev = match read_expected_rev(EXPECTED_REV_FILE) {
        Some(rev) => rev,
        None => {
            println!(
                "cargo:warning=warrend coherence guard: {EXPECTED_REV_FILE} is missing or has no \
                 rev line; skipping the WarrenGuard sibling ancestry check."
            );
            return;
        }
    };

    let sibling = Path::new(SIBLING_DIR);
    if !sibling.join(".git").exists() {
        // No local sibling checkout: the Cargo.toml patch block is presumably
        // absent too (e.g. a published-crate build), so there is nothing to check.
        println!(
            "cargo:warning=warrend coherence guard: no git checkout at {SIBLING_DIR}; skipping the \
             WarrenGuard sibling ancestry check."
        );
        return;
    }

    // Re-run when the sibling's checked-out rev changes, so toggling the sibling
    // to a divergent branch re-triggers the guard. Best-effort: a detached or
    // packed-refs HEAD may not surface as a file, which only costs a missed
    // auto-rerun, never a false failure.
    if let Some(head_ref) = sibling_head_ref_path(sibling) {
        println!("cargo:rerun-if-changed={head_ref}");
    }

    match is_ancestor(sibling, &expected_rev) {
        AncestryResult::IsAncestor => {}
        AncestryResult::NotAncestor => {
            panic!(
                "WarrenGuard coherence guard FAILED.\n\
                 The local sibling {SIBLING_DIR} does not contain engine rev {expected_rev},\n\
                 which the pinned `warren-sdk` git tag (see Cargo.toml) was built against.\n\
                 Building now would compile the SDK against a mismatched protocol engine.\n\n\
                 Fix one of:\n\
                 1. Check out / fast-forward the warrenguard sibling to a rev that contains\n\
                    {expected_rev} (the engine the current SDK tag needs), or\n\
                 2. If you intentionally bumped the engine, update BOTH the `warren-sdk` tag in\n\
                    Cargo.toml AND {EXPECTED_REV_FILE} together (set it to the new tag's\n\
                    .warrenguard-version)."
            );
        }
        AncestryResult::Unknown(reason) => {
            // git absent or the expected rev simply is not present in the sibling
            // object DB yet (e.g. it has not been fetched). Treat as inconclusive,
            // not as a definitive mismatch: warn and let the compile proceed.
            println!(
                "cargo:warning=warrend coherence guard: could not verify the WarrenGuard sibling \
                 ancestry ({reason}); skipping the check."
            );
        }
    }
}

/// First non-empty, non-comment (`#`) line of the expected-rev file, trimmed.
fn read_expected_rev(path: &str) -> Option<String> {
    let contents = std::fs::read_to_string(path).ok()?;
    contents
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty() && !line.starts_with('#'))
        .map(str::to_owned)
}

/// Path to the sibling's HEAD ref file, for `rerun-if-changed`, when it exists.
fn sibling_head_ref_path(sibling: &Path) -> Option<String> {
    let head = sibling.join(".git").join("HEAD");
    let contents = std::fs::read_to_string(&head).ok()?;
    if let Some(rest) = contents.trim().strip_prefix("ref:") {
        let ref_path = sibling.join(".git").join(rest.trim());
        if ref_path.exists() {
            return ref_path.to_str().map(str::to_owned);
        }
    }
    // Detached HEAD: the rev lives directly in .git/HEAD.
    head.to_str().map(str::to_owned)
}

enum AncestryResult {
    IsAncestor,
    NotAncestor,
    Unknown(String),
}

fn is_ancestor(sibling: &Path, expected_rev: &str) -> AncestryResult {
    let output = Command::new("git")
        .arg("-C")
        .arg(sibling)
        .args(["merge-base", "--is-ancestor", expected_rev, "HEAD"])
        .output();

    match output {
        Ok(out) => match out.status.code() {
            // 0 = expected_rev is an ancestor of HEAD.
            Some(0) => AncestryResult::IsAncestor,
            // 1 = it is reachable but NOT an ancestor (a definitive mismatch).
            Some(1) => AncestryResult::NotAncestor,
            // Any other code (e.g. 128) means git could not resolve a rev: the
            // expected rev is absent from the sibling, or HEAD is unborn. Not a
            // definitive non-ancestor, so do not hard-fail.
            other => AncestryResult::Unknown(format!(
                "git merge-base exited with {other:?}: {}",
                String::from_utf8_lossy(&out.stderr).trim()
            )),
        },
        Err(e) => AncestryResult::Unknown(format!("could not run git: {e}")),
    }
}
