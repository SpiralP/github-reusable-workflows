#!/usr/bin/env bash

NEW_VERSION="$1"
test -z "$NEW_VERSION" && echo 'NEW_VERSION missing' && exit 1
test -z "$REPLACE_FILES" && echo 'REPLACE_FILES missing' && exit 1
test -z "$PACKAGE_NAME" && echo 'PACKAGE_NAME missing' && exit 1

if test -n "${VERSION_METADATA:-}"; then
  version_metadata_clean=$(echo "$VERSION_METADATA" | tr ' ' '.')
  NEW_VERSION="$NEW_VERSION+$version_metadata_clean"
fi

IFS=$'\n'
for path in $REPLACE_FILES; do
  filename="$(basename "$path")"
  if test "$filename" = "Cargo.toml" || test "$filename" = "Cargo.lock"; then
    echo "Replacing version in $path"
    sd \
      "(name = \"${PACKAGE_NAME}[^\"]*\"\nversion = \")[^\"]+(\")" \
      "\${1}${NEW_VERSION}\${2}" \
      "$path"
  elif test "$filename" = "package.json" || test "$filename" = "package-lock.json"; then
    echo "Replacing version in $path"
    sd \
      "(\s+\"name\": \"${PACKAGE_NAME}[^\"]*\",\n\s+\"version\": \")[^\"]+(\")" \
      "\${1}${NEW_VERSION}\${2}" \
      "$path"
  else
    echo "Unsupported filename: $filename"
    exit 1
  fi

  if git diff --exit-code -- "$path"; then
    echo "Error: $path was not modified!"
    exit 1
  fi
done
