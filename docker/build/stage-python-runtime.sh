#!/usr/bin/env bash
# Lay a Python runtime bundle (source-python-runtime, unpacked by src/makefiles/python-runtime.cmake)
# over a release tree; used by build.sh and build-windows.sh:
#
#   docker/build/stage-python-runtime.sh <unpacked bundle> <release dir> <out dir>
#
# The bundle replaces the repository's Python3/ and its compiled site-packages, which must have
# the versions in site-packages/requirements.txt (the bundle's manifest lists them). Its
# manifest is copied to <out dir>/python-runtime.txt.
set -euo pipefail
RT=${1:?unpacked bundle}
REL=${2:?release dir}
OUT=${3:?out dir}
REPO=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
REQ=$REPO/addons/source-python/packages/site-packages/requirements.txt
SITE=addons/source-python/packages/site-packages

while IFS='=' read -r key have; do
    want=$(tr 'A-Z-' 'a-z_' < "$REQ" | tr -d '\r' | sed -n "s/^$key==//p")
    if [ -n "$want" ] && [ "$have" != "$want" ]; then
        echo "!! python runtime has $key $have, requirements.txt says $want" >&2; exit 1
    fi
done < <(tr -d '\r' < "$RT/manifest.txt")

rm -rf "$REL/addons/source-python/Python3"
rm -f "$REL/$SITE"/_sysconfigdata_*.py
for p in "$RT/runtime/$SITE"/*; do
    rm -rf "$REL/$SITE/$(basename "$p")"
done
cp -r "$RT/runtime/." "$REL/"
cp "$RT/manifest.txt" "$OUT/python-runtime.txt"
echo "   python runtime $(sed -n 's/^release=//p' "$RT/manifest.txt" | tr -d '\r') ($(sed -n 's/^platform=//p' "$RT/manifest.txt" | tr -d '\r'))"
