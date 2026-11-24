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
#                python-runtime.txt  the Python runtime's manifest
#
# Env:
#   ARCH         x86 (default) or x86_64 (64-bit servers: tf2, css, dods, hl2dm)
#   HL2SDK_REV   hl2sdk commit/branch to build against (default: the branch head, like Build.sh)
#   JOBS         parallel compile jobs (default: nproc; each Boost.Python unit needs 1-2 GB RAM)
#   SP_PYTHON_RUNTIME_ARCHIVE  local Python runtime bundle (.tar.gz) to build and ship with,
#                instead of the release pinned in src/makefiles/python-runtime.cmake
#
# Only tracked files are used (as they are in the working tree), so local build outputs and
# SDK checkouts under src/ don't leak in. Building happens in <out-dir>/work.
#
# The build runs in manylinux_2_28 (AlmaLinux 8, glibc 2.28) with gcc-toolset's GCC 14, which
# links the C++ features newer than the system libstdc++ 8 statically: the binaries need only
# glibc 2.28 and libstdc++ 8's symbol versions, like the Python runtime they embed. The image is
# manylinux_2_28_i686 for x86 and manylinux_2_28_x86_64 for x86_64. The i686 image's userland is
# 32-bit, and 32-bit glibc creates sockets with socketcall(2), which Docker's default seccomp
# profile refuses (Docker 29.4 on GitHub's runners), so that container runs without seccomp;
# that's also why it isn't a Dockerfile (docker build can't turn seccomp off).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(git -C "$HERE" rev-parse --show-toplevel)
BRANCH=${1:?usage: build.sh <branch> <out-dir>}
OUT=$(realpath -m "${2:?usage: build.sh <branch> <out-dir>}")
JOBS=${JOBS:-$(nproc)}
ARCH=${ARCH:-x86}
case $ARCH in
    x86) BUILD_IMAGE=quay.io/pypa/manylinux_2_28_i686@sha256:baf927c001d9dfead35e53de68b2c113b623155b7a878cc45e2e1ad61c9fb5e7
         SECCOMP=(--security-opt seccomp=unconfined) ;;
    x86_64) BUILD_IMAGE=quay.io/pypa/manylinux_2_28_x86_64@sha256:d086f64cddcace250ef0f0073583c51b8298159303290a730c9f59bd91edfd2c
            SECCOMP=() ;;
    *) echo "ARCH must be x86 or x86_64, not $ARCH" >&2; exit 2 ;;
esac
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

echo ">> building $BRANCH ($ARCH) with $JOBS jobs"
cmake_args=(-DSP_ARCH=$ARCH)
if [ -n "${SP_PYTHON_RUNTIME_ARCHIVE:-}" ]; then
    cp "$SP_PYTHON_RUNTIME_ARCHIVE" "$WORK/python-runtime.tar.gz"
    cmake_args+=(-DSP_PYTHON_RUNTIME_ARCHIVE=/work/python-runtime.tar.gz)
fi
# In the container: build as the calling user.
cat > "$WORK/build-in-container.sh" <<EOF
set -e
groupadd -o -g "$(id -g)" builder
useradd -o -u "$(id -u)" -g "$(id -g)" -M -d /tmp builder
exec runuser -u builder -- env HOME=/tmp bash -ec '
    cmake . -BBuilds/Linux/$BRANCH -DBRANCH=$BRANCH ${cmake_args[*]}
    make -C Builds/Linux/$BRANCH -j$JOBS
    # Both binaries must export only CreateInterface (makefiles/linux/exports.map).
    for so in Builds/Linux/$BRANCH/core.so Builds/Linux/$BRANCH/source-python.so; do
        exported=\$(nm -D --defined-only \$so | awk "{print \\\$3}" | sort -u)
        if [ "\$exported" != CreateInterface ]; then
            echo "!! \$so exports more than CreateInterface:" >&2
            echo "\$exported" | head -20 >&2
            exit 1
        fi
    done'
EOF
set +e
docker run --rm "${SECCOMP[@]}" -v "$WORK:/work" -w /work/src "$BUILD_IMAGE" bash /work/build-in-container.sh > "$OUT/build.log" 2>&1
rc=$?
set -e
if [ $rc != 0 ]; then
    echo "!! build failed (exit $rc); last lines of $OUT/build.log:" >&2
    grep -E "error|Error" "$OUT/build.log" | grep -v -- "-Werror" | head -20 >&2
    tail -20 "$OUT/build.log" >&2
    exit 1
fi

echo ">> staging $OUT/release"
B=$WORK/src/Builds/Linux/$BRANCH
git -C "$REPO" ls-files -z addons cfg logs resource sound | (cd "$REPO" && tar -c --null -T -) \
    | tar -x -C "$OUT/release"
# The Python runtime replaces the repository's vendored Linux Python: its Python3/ (stdlib,
# lib-dynload, plat-linux) and its compiled site-packages.
"$HERE/stage-python-runtime.sh" "$B/python-runtime" "$OUT/release" "$OUT"
cp "$B/source-python.so" "$OUT/release/addons/"
mkdir -p "$OUT/release/addons/source-python/bin"
cp "$B/core.so" "$OUT/release/addons/source-python/bin/"
sha256sum "$B/core.so" "$B/source-python.so" | sed "s|$B/|   |"
rm -rf "$WORK"
