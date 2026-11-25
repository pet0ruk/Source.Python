#!/usr/bin/env bash
# Download the latest Metamod:Source build of a branch (default 1.12) and unpack its addons/ into
# a directory, for the harness's EXTRA_ADDONS (to test Source.Python next to Metamod:Source):
#
#   docker/harness/tools/get_metamod.sh <linux|windows> <dir> [branch]
#
# A build has the 32-bit and the 64-bit binaries (addons/metamod.vdf, addons/metamod_x64.vdf);
# the server loads the one for its architecture.
set -euo pipefail
PLATFORM=${1:?usage: get_metamod.sh <linux|windows> <dir> [branch]}
DIR=${2:?usage: get_metamod.sh <linux|windows> <dir> [branch]}
BRANCH=${3:-1.12}
PYTHON=$(command -v python3 || command -v python)
base=https://mms.alliedmods.net/mmsdrop/$BRANCH
name=$(curl -fsSL "$base/mmsource-latest-$PLATFORM" | tr -d '\r\n')
[ -n "$name" ] || { echo "no Metamod:Source $BRANCH build for $PLATFORM" >&2; exit 1; }
echo ">> Metamod:Source $name"
mkdir -p "$DIR"
tmp=$(mktemp -d)
curl -fsSL "$base/$name" -o "$tmp/$name"
case $name in
    *.tar.gz) tar -xzf "$tmp/$name" -C "$DIR" ;;
    *.zip) "$PYTHON" -I -m zipfile -e "$tmp/$name" "$DIR" ;;
    *) echo "unknown archive $name" >&2; exit 1 ;;
esac
rm -rf "$tmp"
echo "$name" > "$DIR/metamod-version.txt"
