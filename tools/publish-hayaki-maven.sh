#!/bin/bash
#
# Publishes the Hayaki Engine to the `maven` branch of this repository. Hayaki for
# Android resolves it from https://raw.githubusercontent.com/amemiya02/Anki-Android-Backend/maven/
#
# Run after a full build (`ALL_ARCHS=1 RELEASE=1 ROBOLECTRIC_HOST_ONLY=1 cargo run -p build_rust`
# on Linux), so that the AAR has every Android ABI and the testing JAR has the Linux host
# library. The version is upstream's VERSION_NAME plus the Engine fork commit, for example
# 0.1.77-anki26.09.4-hayaki.3e8f35062. A published version is never replaced: a rebuild is
# not byte-identical, and Hayaki pins the bundled SvelteKit CSP hash of the one it uses.
# `--print-version` prints the version and exits. It pushes to $HAYAKI_MAVEN_REMOTE (default origin),
# which must be amemiya02/Anki-Android-Backend.

set -euo pipefail
cd "$(dirname "$0")/.."

base=$(sed -n 's/^VERSION_NAME=//p' gradle.properties)
fork=$(git -C anki rev-parse --short=9 HEAD)
version="${base}-hayaki.${fork}"
if [ "${1:-}" = "--print-version" ]; then
  echo "$version"
  exit 0
fi
repo=$(mktemp -d)
site=$(mktemp -d)
remote=${HAYAKI_MAVEN_REMOTE:-origin}

RUNNING_FROM_BUILD_SCRIPT=1 ./gradlew -q \
  rsdroid:publishToMavenLocal rsdroid-android:publishToMavenLocal rsdroid-testing:publishToMavenLocal \
  -x test -PhayakiUnsigned -PGROUP=io.github.amemiya02 -PVERSION_NAME="$version" \
  -Dmaven.repo.local="$repo"

if git ls-remote --exit-code --heads "$remote" maven >/dev/null; then
  git fetch -q "$remote" maven
  git worktree add -q "$site" FETCH_HEAD
else
  git worktree add -q --detach "$site"
  git -C "$site" checkout -q --orphan maven
  git -C "$site" rm -rfq .
fi

if [ -e "$site/io/github/amemiya02/anki-backend-android/$version" ]; then
  echo "$version is already published; not replacing it"
  git worktree remove --force "$site"
  exit 0
fi

# maven-metadata-local.xml is only for Maven Local; the fixed versions need no metadata.
rsync -a --exclude maven-metadata-local.xml "$repo/io" "$site/"
git -C "$site" add -A io
if git -C "$site" diff --cached --quiet; then
  echo "Nothing new to publish for $version"
else
  git -C "$site" commit -q --no-verify -m "Publish Hayaki Engine $version"
  git -C "$site" push -q "$remote" HEAD:refs/heads/maven
  echo "Published $version"
fi
git worktree remove --force "$site"
