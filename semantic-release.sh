#!/usr/bin/env bash

merged_extends="$(mktemp --suffix .json)"
trap 'rm -f "$merged_extends"' EXIT

cat "$BASE_CONFIG_PATH" > "$merged_extends"
unset BASE_CONFIG_PATH

if test -n "${REPLACE_FILES:-}"; then
  temp1="$(mktemp)"
  jq -n \
    --arg script "nix run --print-build-logs github:SpiralP/github-reusable-workflows/${WORKFLOW_SHA:-main}#replace-versions --" \
    --arg assets "$REPLACE_FILES" \
    '{
      plugins: [
        [
          "@semantic-release/exec",
          {
            prepareCmd: "\($script) ${nextRelease.version}"
          }
        ],
        [
          "@semantic-release/git",
          {
            assets: $assets | split("\n") | map(select(length > 0)),
            message: "chore(release): ${nextRelease.version}\n\n${nextRelease.notes}"
          }
        ]
      ]
    }' > "$temp1"

  temp2="$(mktemp)"
  jq -s -f "$MERGE_JQ_PATH" \
    "$merged_extends" \
    "$temp1" \
    > "$temp2"
  rm -f "$temp1"

  cat "$temp2" > "$merged_extends"
  rm -f "$temp2"
fi

if test -n "${ASSETS:-}"; then
  temp1="$(mktemp)"
  jq -n \
    --arg assets "$ASSETS" \
    '{
      plugins: [
        [
          "@semantic-release/github",
          {
            assets: $assets | split("\n") | map(select(length > 0) | ".release-assets/\(.)")
          }
        ]
      ]
    }' > "$temp1"

  temp2="$(mktemp)"
  jq -s -f "$MERGE_JQ_PATH" \
    "$merged_extends" \
    "$temp1" \
    > "$temp2"
  rm -f "$temp1"

  cat "$temp2" > "$merged_extends"
  rm -f "$temp2"
fi

if test "${CARGO_PUBLISH:-}" = "true"; then
  temp1="$(mktemp)"
  jq -n \
    '{
      plugins: [
        [
          "@semantic-release/exec",
          {
            publishCmd: "cargo publish --no-verify"
          }
        ]
      ]
    }' > "$temp1"

  temp2="$(mktemp)"
  jq -s -f "$MERGE_JQ_PATH" \
    "$merged_extends" \
    "$temp1" \
    > "$temp2"
  rm -f "$temp1"

  cat "$temp2" > "$merged_extends"
  rm -f "$temp2"
fi

if test -n "${BUILD_WORKFLOW:-}"; then
  publish_cmd="nix run --print-build-logs github:SpiralP/github-reusable-workflows/${WORKFLOW_SHA:-main}#build-and-download -- \"\${nextRelease.gitTag}\" \"$BUILD_WORKFLOW\""

  temp1="$(mktemp)"
  # Insert an exec(publishCmd) plugin immediately before @semantic-release/github.
  # semantic-release pushes the release tag between the prepare and publish
  # phases, so by the time publishCmd fires, the tag exists on the remote and
  # `--ref <tag>` resolves to the exact release commit. Artifacts land in
  # .release-assets/ before @semantic-release/github globs them.
  #
  # On failure, build-and-download.sh deletes the tag itself via an EXIT trap.
  # We don't register a failCmd because @semantic-release/exec doesn't wrap
  # publishCmd errors in SemanticReleaseError, so semantic-release's callFail
  # filters them out and never invokes fail hooks.
  jq --arg publish "$publish_cmd" '
    ["@semantic-release/exec", {publishCmd: $publish}] as $exec_plugin
    | .plugins as $orig
    | ($orig | map(if type == "array" then .[0] else . end) | index("@semantic-release/github")) as $idx
    | if $idx == null then
        .plugins = $orig + [$exec_plugin]
      else
        .plugins = $orig[:$idx] + [$exec_plugin] + $orig[$idx:]
      end
  ' "$merged_extends" > "$temp1"
  cat "$temp1" > "$merged_extends"
  rm -f "$temp1"
fi
unset BUILD_WORKFLOW

if test -n "${EXTENDS:-}"; then
  temp1="$(mktemp)"
  jq -s -f "$MERGE_JQ_PATH" \
    "$merged_extends" \
    "$EXTENDS" \
    > "$temp1"
  cat "$temp1" > "$merged_extends"
  rm -f "$temp1"
fi
unset EXTENDS

jq . "$merged_extends"

"$NODE_PATH/.bin/semantic-release" --extends "$merged_extends" "$@"
