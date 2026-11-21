#!/usr/bin/env bash
# Build Source.Python for Linux from this repository's working tree, in Docker.
#
#   docker/build/build.sh <branch> <out-dir>
#
#   <branch>   a build branch from src/makefiles/branch (tf2, css, dods, hl2dm, l4d2, ...)
#   out-dir    receives:
#                release/      addons cfg logs resource sound + the two binaries, ready for
#                              docker/harness/run.sh or a server
#                build.log     cmake + make output
#                hl2sdk.txt    the hl2sdk commit that was built against
#
# Env:
#   HL2SDK_REV   hl2sdk commit/branch to build against (default: the branch head, like Build.sh)
#   JOBS         parallel compile jobs (default: nproc; each Boost.Python unit needs 1-2 GB RAM)
#   CCACHE_DIR   host directory for ccache (optional; speeds up rebuilds)
#
# Only tracked files are used (as they are in the working tree), so local build outputs and
# SDK checkouts under src/ don't leak in. Building happens in <out-dir>/work.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(git -C "$HERE" rev-parse --show-toplevel)
BRANCH=${1:?usage: build.sh <branch> <out-dir>}
OUT=$(realpath -m "${2:?usage: build.sh <branch> <out-dir>}")
JOBS=${JOBS:-$(nproc)}
[ -f "$REPO/src/makefiles/branch/$BRANCH.cmake" ] || { echo "unknown branch '$BRANCH'" >&2; exit 2; }

WORK=$OUT/work
rm -rf "$WORK" "$OUT/release"; mkdir -p "$WORK" "$OUT/release"

echo ">> source: working tree of $REPO ($(git -C "$REPO" rev-parse --short HEAD))"
git -C "$REPO" ls-files -z src | (cd "$REPO" && tar -c --null -T -) | tar -x -C "$WORK"

REV=${HL2SDK_REV:-$BRANCH}
SDK=$WORK/src/hl2sdk/$BRANCH
echo ">> hl2sdk: alliedmodders/hl2sdk @ $REV"
mkdir -p "$SDK"
git -C "$SDK" init -q
git -C "$SDK" fetch -q --depth 1 https://github.com/alliedmodders/hl2sdk.git "$REV"
git -C "$SDK" checkout -q FETCH_HEAD
git -C "$SDK" rev-parse HEAD > "$OUT/hl2sdk.txt"
echo "   commit $(cat "$OUT/hl2sdk.txt")"
# Same as Build.sh: whole-file overlays from src/patches/<branch>
if [ -d "$WORK/src/patches/$BRANCH" ]; then
    cp -r "$WORK/src/patches/$BRANCH/." "$SDK/"
fi

echo ">> building $BRANCH with $JOBS jobs"
docker build -q -t sp-build "$HERE" >/dev/null
cache_args=()
launcher=()
if [ -n "${CCACHE_DIR:-}" ]; then
    mkdir -p "$CCACHE_DIR"
    cache_args=(-v "$(realpath "$CCACHE_DIR"):/ccache" -e CCACHE_DIR=/ccache
                -e CCACHE_BASEDIR=/work -e CCACHE_NOHASHDIR=1)
    launcher=(-DCMAKE_CXX_COMPILER_LAUNCHER=ccache)
fi
set +e
docker run --rm -u "$(id -u):$(id -g)" -v "$WORK:/work" -w /work/src "${cache_args[@]}" \
    sp-build bash -c "
        set -e
        cmake . -BBuilds/Linux/$BRANCH -DBRANCH=$BRANCH ${launcher[*]}
        make -C Builds/Linux/$BRANCH -j$JOBS
        [ -z \"\${CCACHE_DIR:-}\" ] || ccache -s" > "$OUT/build.log" 2>&1
rc=$?
set -e
if [ $rc != 0 ]; then
    echo "!! build failed (exit $rc); last lines of $OUT/build.log:" >&2
    grep -E "error|Error" "$OUT/build.log" | grep -v -- "-Werror" | head -20 >&2
    tail -20 "$OUT/build.log" >&2
    exit 1
fi
grep -A12 "^cache directory\|^Summary:" "$OUT/build.log" | grep -iE "hit|miss" | head -4 || true

echo ">> staging $OUT/release"
B=$WORK/src/Builds/Linux/$BRANCH
git -C "$REPO" ls-files -z addons cfg logs resource sound | (cd "$REPO" && tar -c --null -T -) \
    | tar -x -C "$OUT/release"
cp "$B/source-python.so" "$OUT/release/addons/"
mkdir -p "$OUT/release/addons/source-python/bin"
cp "$B/core.so" "$OUT/release/addons/source-python/bin/"
sha256sum "$B/core.so" "$B/source-python.so" | sed "s|$B/|   |"
rm -rf "$WORK"
