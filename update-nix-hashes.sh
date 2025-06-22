#!/usr/bin/env bash

NPM_ATTRIBUTE="$1"
PACKAGE_LOCK_PATH="$2"

OLD_HASH="$(nix eval --no-update-lock-file --raw ".#$NPM_ATTRIBUTE.npmDepsHash")"
NEW_HASH="$(prefetch-npm-deps "$PACKAGE_LOCK_PATH" 2>/dev/null)"

echo "$OLD_HASH" "$NEW_HASH"
test -z "$OLD_HASH" && exit 1
test -z "$NEW_HASH" && exit 1
test "$OLD_HASH" = "$NEW_HASH" && exit 0

if ! grep -q "$OLD_HASH" flake.nix; then
  echo "couldn't find old hash in flake.nix"
  exit 1
fi
sd --fixed-strings "$OLD_HASH" "$NEW_HASH" flake.nix
if ! grep -q "$NEW_HASH" flake.nix; then
  echo "couldn't find new hash in flake.nix"
  exit 1
fi
