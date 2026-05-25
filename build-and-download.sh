#!/usr/bin/env bash
# Invoked from semantic-release's `publish` lifecycle (via @semantic-release/exec
# publishCmd) on the release runner, AFTER semantic-release pushes the release
# tag and BEFORE @semantic-release/github creates the release. Dispatches a
# build workflow on the tag (which is immutable, so `--ref <tag>` checks out
# the exact released commit), waits for it, and downloads its artifacts into
# `$RUNNER_TEMP/release-assets/` so that @semantic-release/github attaches them
# to the release. Staging outside the repo working tree keeps `cargo publish`
# and `@semantic-release/git` from tripping their dirty-tree checks.
#
# Args:
#   $1  tag name (pass via `${nextRelease.gitTag}` from semantic-release)
#   $2  workflow filename (e.g. `build.yml`); must support workflow_dispatch.
#
# If this script exits non-zero, the EXIT trap deletes the just-pushed tag
# (locally and on the remote) so a retry of the release pipeline starts from
# a clean state. We can't rely on semantic-release's failCmd hook here:
# @semantic-release/exec doesn't wrap publishCmd errors in
# SemanticReleaseError, so semantic-release's callFail() filters them out
# and never invokes the registered failCmd.
set -euo pipefail

TAG="${1:?tag name required}"
WORKFLOW="${2:?workflow filename required}"

cleanup() {
  status=$?
  if test "$status" -ne 0; then
    echo "Build dispatch/watch/download failed (status=$status); deleting tag $TAG" >&2
    git push --delete origin "$TAG" || echo "warning: could not delete remote tag $TAG" >&2
    git tag -d "$TAG" || echo "warning: could not delete local tag $TAG" >&2
  fi
}
trap cleanup EXIT

echo "Dispatching $WORKFLOW on tag=$TAG"
# gh 2.50+ prints the run's HTML URL on stdout in non-TTY mode (single line),
# from the dispatch endpoint's `return_run_details` response. URL format:
#   https://github.com/<owner>/<repo>/actions/runs/<run_id>
RUN_URL="$(gh workflow run "$WORKFLOW" --ref "$TAG")"

RUN_ID="${RUN_URL##*/}"
case "$RUN_ID" in
  '' | *[!0-9]*)
    echo "Could not parse run ID from \`gh workflow run\` output: $RUN_URL" >&2
    exit 1
    ;;
esac
echo "Dispatched run: $RUN_URL (id=$RUN_ID)"

# Surface the run-id to the caller via the workflow's `dispatched-run-id`
# output. The path is set by the Release step in the reusable release
# workflow (analogous to VERSION_OUTPUT_FILE / TAG_OUTPUT_FILE). Written
# eagerly so the output is set even if watch/download later fails — though
# in the failure path the EXIT trap deletes the tag, so the caller's
# `deploy-docs` job gates on `needs.release.outputs.tag` and skips anyway.
if test -n "${DISPATCHED_RUN_ID_FILE:-}"; then
  printf '%s' "$RUN_ID" > "$DISPATCHED_RUN_ID_FILE"
fi

echo "Watching run $RUN_ID"
gh run watch "$RUN_ID" --compact --exit-status --interval 5

ASSETS_DIR="${RUNNER_TEMP:?RUNNER_TEMP must be set}/release-assets"
mkdir -p "$ASSETS_DIR"
echo "Downloading artifacts from run $RUN_ID into $ASSETS_DIR/"
gh run download "$RUN_ID" --dir "$ASSETS_DIR"

# `gh run download` places each artifact in its own subdirectory; flatten so
# the asset globs in semantic-release.sh match against bare filenames.
find "$ASSETS_DIR" -mindepth 2 -type f -exec mv -t "$ASSETS_DIR/" {} +
find "$ASSETS_DIR" -mindepth 1 -type d -empty -delete

echo "Final assets:"
ls -la "$ASSETS_DIR"
