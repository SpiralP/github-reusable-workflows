#!/usr/bin/env bash
# Invoked from semantic-release's `publish` lifecycle (via @semantic-release/exec
# publishCmd) on the release runner, AFTER semantic-release pushes the release
# tag and BEFORE @semantic-release/github creates the release. Dispatches a
# build workflow on the tag (which is immutable, so `--ref <tag>` checks out
# the exact released commit), waits for it, and downloads its artifacts into
# `.release-assets/` so that @semantic-release/github attaches them to the
# release.
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

echo "Watching run $RUN_ID"
gh run watch "$RUN_ID" --compact --exit-status --interval 5

mkdir -p .release-assets
echo "Downloading artifacts from run $RUN_ID into .release-assets/"
gh run download "$RUN_ID" --dir .release-assets

# `gh run download` places each artifact in its own subdirectory; flatten so
# `.release-assets/*.{so,dll,dylib}` matches the upstream release.yml's glob.
find .release-assets -mindepth 2 -type f -exec mv -t .release-assets/ {} +
find .release-assets -mindepth 1 -type d -empty -delete

echo "Final assets:"
ls -la .release-assets
