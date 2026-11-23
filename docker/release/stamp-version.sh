#!/usr/bin/env bash
# Write the release's version and commit into core/version.py (VERSION = None and
# GIT_COMMIT = None in the repository), in the working tree that is then built:
#
#   docker/release/stamp-version.sh <version> <commit>
#
# The file may have CRLF line endings (a Windows checkout).
set -euo pipefail
VERSION=${1:?usage: stamp-version.sh <version> <commit>}
COMMIT=${2:?usage: stamp-version.sh <version> <commit>}
REPO=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
FILE=$REPO/addons/source-python/packages/source-python/core/version.py
[[ $VERSION =~ ^[0-9A-Za-z.-]+$ && $COMMIT =~ ^[0-9a-f]{40}$ ]] || { echo "bad version or commit" >&2; exit 2; }
sed -i -e "s/^VERSION = None\(\r\?\)$/VERSION = '$VERSION'\1/" \
       -e "s/^GIT_COMMIT = None\(\r\?\)$/GIT_COMMIT = '$COMMIT'\1/" "$FILE"
grep -q "^VERSION = '$VERSION'" "$FILE" && grep -q "^GIT_COMMIT = '$COMMIT'" "$FILE" \
    || { echo "!! could not stamp $FILE" >&2; exit 1; }
echo "stamped $VERSION ($COMMIT)"
