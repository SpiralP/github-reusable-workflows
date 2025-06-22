#!/usr/bin/env bash

VERSION="$1"
TAG="$2"
test -z "$VERSION" && echo 'VERSION missing' && exit 1
test -z "$TAG" && echo 'TAG missing' && exit 1

if test -n "${VERSION_OUTPUT_FILE:-}"; then
    echo "Writing version to $VERSION_OUTPUT_FILE"
    echo "$VERSION" | tee "$VERSION_OUTPUT_FILE"
else
    echo "VERSION_OUTPUT_FILE not set, skipping writing version."
fi

if test -n "${TAG_OUTPUT_FILE:-}"; then
    echo "Writing tag to $TAG_OUTPUT_FILE"
    echo "$TAG" | tee "$TAG_OUTPUT_FILE"
else
    echo "TAG_OUTPUT_FILE not set, skipping writing tag."
fi
