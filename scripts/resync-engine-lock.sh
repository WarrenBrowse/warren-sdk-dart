#!/usr/bin/env bash
# Resync native/warren_sdk_frb/Cargo.lock to the pinned engine tag.
#
# The glue crate pins the engine by git tag and [patch]es warrenguard +
# warren-contract to sibling checkouts at the exact revs that tag expects (its
# .warrenguard-version / .warren-contract-version). Bumping the engine tag
# changes the resolved graph, so the committed lock must be regenerated or CI's
# `cargo build --locked` fails. This does that regeneration reproducibly, in an
# isolated temp workspace, WITHOUT touching any sibling checkout you may have.
#
# Usage (from anywhere in the repo):
#   scripts/resync-engine-lock.sh
# then commit the updated Cargo.toml (your tag bump) + Cargo.lock together.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
FRB_DIR="${REPO_ROOT}/native/warren_sdk_frb"
CARGO_TOML="${FRB_DIR}/Cargo.toml"

ENGINE_TAG="$(sed -n 's/^[[:space:]]*warren-sdk[[:space:]]*=.*warren-sdk-rs\.git.*tag[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "${CARGO_TOML}")"
[ -n "${ENGINE_TAG}" ] || { echo "error: could not parse the warren-sdk engine tag from ${CARGO_TOML}" >&2; exit 1; }

# Same host/org/transport as this repo's origin, so the clones reuse the git
# auth that already works here (ssh or https token, whichever origin uses).
ORIGIN_URL="$(git -C "${REPO_ROOT}" remote get-url origin)"
BASE="${ORIGIN_URL%warren-sdk-dart*}"   # e.g. git@github.com:WarrenBrowse/ or https://github.com/WarrenBrowse/

echo "==> engine tag: ${ENGINE_TAG}"

TMP="$(mktemp -d)"
WORKTREE="${TMP}/warren-sdk-dart"
cleanup() {
  git -C "${REPO_ROOT}" worktree remove --force "${WORKTREE}" 2>/dev/null || true
  rm -rf "${TMP}"
}
trap cleanup EXIT

# Read the sibling revs the engine itself pins at that tag (shallow tag clone).
git clone --quiet --depth 1 --branch "${ENGINE_TAG}" "${BASE}warren-sdk-rs.git" "${TMP}/engine-pin"
WG_REV="$(tr -d '[:space:]' < "${TMP}/engine-pin/.warrenguard-version")"
WC_REV="$(tr -d '[:space:]' < "${TMP}/engine-pin/.warren-contract-version")"
[ -n "${WG_REV}" ] && [ -n "${WC_REV}" ] || { echo "error: engine tag ${ENGINE_TAG} is missing .warrenguard-version / .warren-contract-version" >&2; exit 1; }
echo "==> warrenguard rev:     ${WG_REV}"
echo "==> warren-contract rev: ${WC_REV}"

# Isolated workspace: a detached worktree of HEAD (so the layout the [patch]
# relative paths expect exists) with the two siblings beside it at the pinned
# revs. Nothing here touches the repo's own working tree or your siblings.
git -C "${REPO_ROOT}" worktree add --quiet --detach "${WORKTREE}" HEAD
git clone --quiet --filter=blob:none "${BASE}warrenguard.git" "${TMP}/warrenguard"
git -C "${TMP}/warrenguard" checkout --quiet "${WG_REV}"
git clone --quiet --filter=blob:none "${BASE}warren-contract.git" "${TMP}/warren-contract"
git -C "${TMP}/warren-contract" checkout --quiet "${WC_REV}"

# Reconcile the committed lock minimally: `cargo metadata` starts from the
# existing Cargo.lock and only changes entries the resolved graph requires, so
# unrelated crates stay pinned (unlike `generate-lockfile`, which bumps all to
# latest). git-fetch-with-cli reuses your git credentials for the private deps.
echo "==> reconciling Cargo.lock"
( cd "${WORKTREE}/native/warren_sdk_frb" && CARGO_NET_GIT_FETCH_WITH_CLI=true cargo metadata --format-version 1 >/dev/null )

if cmp -s "${WORKTREE}/native/warren_sdk_frb/Cargo.lock" "${FRB_DIR}/Cargo.lock"; then
  echo "==> Cargo.lock already in sync, nothing to do."
else
  cp "${WORKTREE}/native/warren_sdk_frb/Cargo.lock" "${FRB_DIR}/Cargo.lock"
  echo "==> updated ${FRB_DIR#"${REPO_ROOT}/"}/Cargo.lock:"
  git -C "${REPO_ROOT}" --no-pager diff --stat -- native/warren_sdk_frb/Cargo.lock
fi
