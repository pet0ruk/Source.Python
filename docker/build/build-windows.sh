#!/usr/bin/env bash
# Build Source.Python for Windows with MSVC. Runs in Git Bash on Windows (CI: windows-latest)
# and needs git, CMake and Visual Studio with the C++ desktop workload:
#
#   docker/build/build-windows.sh <branch> <out-dir>
#
#   <branch>   a build branch from src/makefiles/branch (tf2, css, dods, hl2dm, l4d2, ...)
#   out-dir    receives:
#                release/      addons cfg logs resource sound + the two DLLs, ready for
#                              docker/harness/run-windows.sh or a server
#                build.log     cmake + build output
#                hl2sdk.txt    the hl2sdk commit that was built against
#
#                python-runtime.txt  the Python runtime's manifest
#
# Env:
#   ARCH         x86 (default) or x86_64 (64-bit servers: tf2, css, dods, hl2dm)
#   HL2SDK_REV   hl2sdk commit/branch to build against (default: the branch head, like Build.bat)
#   SP_PYTHON_RUNTIME_ARCHIVE  local Python runtime bundle (.zip) to build and ship with,
#                instead of the release pinned in src/makefiles/python-runtime.cmake
#
# Unlike build.sh this builds in place, like Build.bat: the SDK is checked out into
# src/hl2sdk/<branch> and the build goes to src/Builds/Windows/<branch> (both gitignored, both
# replaced on every run). The release tree is the tracked files as they are in the working tree.
# Visual Studio's newest generator is used (CMake's default), with a 32-bit (Win32) or, for
# ARCH=x86_64, a 64-bit (x64) target.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(git -C "$HERE" rev-parse --show-toplevel)
BRANCH=${1:?usage: build-windows.sh <branch> <out-dir>}
OUT=$(realpath -m "${2:?usage: build-windows.sh <branch> <out-dir>}")
[ -f "$REPO/src/makefiles/branch/$BRANCH.cmake" ] || { echo "unknown branch '$BRANCH'" >&2; exit 2; }
ARCH=${ARCH:-x86}
case $ARCH in
    x86) VS_PLATFORM=Win32 ;;
    x86_64) VS_PLATFORM=x64 ;;
    *) echo "ARCH must be x86 or x86_64, not $ARCH" >&2; exit 2 ;;
esac
SRC=$REPO/src
SDK=$SRC/hl2sdk/$BRANCH
B=$SRC/Builds/Windows/$BRANCH
rm -rf "$OUT/release" "$SDK" "$B"; mkdir -p "$OUT/release"

echo ">> source: working tree of $REPO ($(git -C "$REPO" rev-parse --short HEAD))"
REV=${HL2SDK_REV:-$BRANCH}
echo ">> hl2sdk: alliedmodders/hl2sdk @ $REV"
mkdir -p "$SDK"
git -C "$SDK" init -q
git -C "$SDK" fetch -q --depth 1 https://github.com/alliedmodders/hl2sdk.git "$REV"
git -C "$SDK" checkout -q FETCH_HEAD
git -C "$SDK" rev-parse HEAD > "$OUT/hl2sdk.txt"
echo "   commit $(cat "$OUT/hl2sdk.txt")"
# Same as Build.bat: whole-file overlays from src/patches/<branch>
if [ -d "$SRC/patches/$BRANCH" ]; then
    cp -r "$SRC/patches/$BRANCH/." "$SDK/"
fi

echo ">> building $BRANCH"
set +e
{
    cmake -S "$SRC" -B "$B" -A "$VS_PLATFORM" -DBRANCH="$BRANCH" -DSP_ARCH="$ARCH" \
        ${SP_PYTHON_RUNTIME_ARCHIVE:+"-DSP_PYTHON_RUNTIME_ARCHIVE=$(cygpath -m "$SP_PYTHON_RUNTIME_ARCHIVE")"} \
        && cmake --build "$B" --config Release --parallel
} > "$OUT/build.log" 2>&1
rc=$?
set -e
if [ $rc != 0 ]; then
    echo "!! build failed (exit $rc); errors from $OUT/build.log:" >&2
    grep -E ": (fatal )?error " "$OUT/build.log" | sort -u | head -30 >&2
    tail -20 "$OUT/build.log" >&2
    exit 1
fi
grep -m1 -E "Building for:|Selecting Windows SDK|The CXX compiler identification" "$OUT/build.log" || true

echo ">> staging $OUT/release"
git -C "$REPO" ls-files -z addons cfg logs resource sound | (cd "$REPO" && tar -c --null -T -) \
    | tar -x -C "$OUT/release"
"$HERE/stage-python-runtime.sh" "$B/python-runtime" "$OUT/release" "$OUT"
cp "$B/Release/source-python.dll" "$OUT/release/addons/"
mkdir -p "$OUT/release/addons/source-python/bin"
cp "$B/Release/core.dll" "$OUT/release/addons/source-python/bin/"
sha256sum "$B/Release/core.dll" "$B/Release/source-python.dll" | sed "s|$B/Release/|   |"
