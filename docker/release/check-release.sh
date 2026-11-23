#!/usr/bin/env bash
# Check that a GitHub release can be built or promoted (needs gh, with GH_TOKEN):
#
#   docker/release/check-release.sh <tag> <promote: true|false>
#
# The tag must be v<MAJOR>.<MINOR>.<PATCH>[-<pre-release>] and the release a published
# pre-release (not a draft). To be promoted to a full release, the version must have no
# pre-release part (sp update ignores those) and be newer than the latest full release.
# Prints version=..., stable=true|false and promote=true|false (for $GITHUB_OUTPUT).
set -euo pipefail
TAG=${1:?usage: check-release.sh <tag> <promote>}
PROMOTE=${2:?usage: check-release.sh <tag> <promote>}
fail() { echo "!! $TAG: $*" >&2; exit 1; }

[[ $TAG =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$ ]] \
    || fail "not v<MAJOR>.<MINOR>.<PATCH>[-<pre-release>]"
VERSION=${TAG#v}
STABLE=$([ -z "${BASH_REMATCH[4]}" ] && echo true || echo false)

state=$(gh release view "$TAG" --json isDraft,isPrerelease -q '"\(.isDraft) \(.isPrerelease)"') \
    || fail "no such release"
[ "$state" = "false true" ] || fail "not a published pre-release (draft, pre-release: $state)"

if [ "$PROMOTE" = true ]; then
    [ "$STABLE" = true ] || fail "a pre-release version can't be made a full release"
    latest=$(gh release list --exclude-drafts --exclude-pre-releases --json tagName -q '.[].tagName' \
        | sed -n 's/^v\([0-9]\+\.[0-9]\+\.[0-9]\+\)$/\1/p' | sort -V | tail -1)
    if [ -n "$latest" ]; then
        newest=$(printf '%s\n' "$latest" "$VERSION" | sort -V | tail -1)
        [ "$newest" = "$VERSION" ] && [ "$latest" != "$VERSION" ] \
            || fail "not newer than the latest release, $latest"
    fi
fi
echo "version=$VERSION"
echo "stable=$STABLE"
echo "promote=$PROMOTE"
