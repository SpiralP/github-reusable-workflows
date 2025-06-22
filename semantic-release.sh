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
  jq -s \
    '(.[0] * .[1]) * { plugins: (.[0].plugins + .[1].plugins) }' \
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
  jq -s \
    '(.[0] * .[1]) * { plugins: (.[0].plugins + .[1].plugins) }' \
    "$merged_extends" \
    "$temp1" \
    > "$temp2"
  rm -f "$temp1"

  cat "$temp2" > "$merged_extends"
  rm -f "$temp2"
fi

if test -n "${EXTENDS:-}"; then
  temp1="$(mktemp)"
  jq -s \
    '(.[0] * .[1]) * { plugins: (.[0].plugins + .[1].plugins) }' \
    "$merged_extends" \
    "$EXTENDS" \
    > "$temp1"
  cat "$temp1" > "$merged_extends"
  rm -f "$temp1"
fi
unset EXTENDS

jq . "$merged_extends"

"$NODE_PATH/.bin/semantic-release" --extends "$merged_extends" "$@"
