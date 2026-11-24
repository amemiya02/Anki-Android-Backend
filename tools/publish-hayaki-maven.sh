#!/bin/bash
#
# Publishes the Hayaki Engine to the `maven` branch of this repository. Hayaki for
# Android resolves it from https://raw.githubusercontent.com/amemiya02/Anki-Android-Backend/maven/
#
# Run after a full build (`ALL_ARCHS=1 RELEASE=1 ./build.sh`), so that the AAR has every
# Android ABI and the testing JAR has the Linux, macOS and Windows host libraries.
# The version is upstream's VERSION_NAME plus the Engine fork commit, for example
# 0.1.77-anki26.09.4-hayaki.3e8f35062. It pushes to $HAYAKI_MAVEN_REMOTE (default origin),
# which must be amemiya02/Anki-Android-Backend.

set -euo pipefail
cd "$(dirname "$0")/.."

base=$(sed -n 's/^VERSION_NAME=//p' gradle.properties)
fork=$(git -C anki rev-parse --short=9 HEAD)
version="${base}-hayaki.${fork}"
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

# maven-metadata-local.xml is only for Maven Local; the fixed versions need no metadata.
(cd "$repo" && find io -type f ! -name 'maven-metadata-local.xml' -print0 | cpio -0pdmu --quiet "$site")
git -C "$site" add -A io
if git -C "$site" diff --cached --quiet; then
  echo "Nothing new to publish for $version"
else
  git -C "$site" commit -q -m "Publish Hayaki Engine $version"
  git -C "$site" push -q "$remote" HEAD:refs/heads/maven
  echo "Published $version"
fi
git worktree remove --force "$site"
