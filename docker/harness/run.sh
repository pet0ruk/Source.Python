#!/usr/bin/env bash
# Run Source.Python's functional tests against a srcds test image (see docker/srcds).
#
#   docker/harness/run.sh <game> <source-python release .zip | extracted dir> [out-dir]
#
#   <game>     a key of docker/srcds/games.json (tf2, css, dods, hl2dm, l4d2, csgo, bms)
#   out-dir    default ./sp-harness-out/<game>; receives results.json, console.log,
#              Source.Python's logs and the gamedata check output
#
# Env:
#   ARCH            x86 (default) or x86_64: run the game's 64-bit server (srcds_run_64) with a
#                   64-bit Source.Python build. For a game whose 64-bit server has no launcher
#                   (games.json: x86_64_launcher, e.g. CS:S), srcds_run_64, srcds_linux64 and
#                   bin/linux64/libsteam_api.so are taken from that game's image (TF2's).
#   SRCDS_IMAGE     image repository (default ghcr.io/pet0ruk/srcds); the tag is <game>
#   GAMES_JSON      per-game settings (default docker/srcds/games.json), e.g. for a game
#                   without a published image
#   PULL=0          don't pull the image first
#   TIMEOUT         seconds before the server is killed (default 240)
#   OVERLAY_REPO=1  copy this repository's tracked addons/cfg/resource/sound files (as they are
#                   in the working tree) over the release, to test Python/data changes against
#                   prebuilt binaries without rebuilding
#   NO_UPDATE=1     don't stage an update for the loader to apply on start (tools/stage_update.sh)
#   EXTRA_ADDONS    a directory laid out like the game directory (e.g. addons/metamod.vdf and
#                   addons/metamod/...) copied into the server as well, to test Source.Python next
#                   to other server plugins
#
# Exit status: 0 if every check passed (skips are allowed), 1 otherwise.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
GAMES_JSON=${GAMES_JSON:-$(cd "$HERE/../srcds" && pwd)/games.json}
GAME=${1:?usage: run.sh <game> <source-python.zip|dir> [out-dir]}
SRC=$(realpath "${2:?source-python release zip or directory}")
OUT=$(realpath -m "${3:-$PWD/sp-harness-out/$GAME}")
SRCDS_IMAGE=${SRCDS_IMAGE:-ghcr.io/pet0ruk/srcds}
TIMEOUT=${TIMEOUT:-240}
ARCH=${ARCH:-x86}
case $ARCH in
    x86) SRCDS_RUN=srcds_run SRCDS_BINARY=./srcds_linux BIN_SUBDIR= TAG_SUFFIX= ELF_CLASS=1 ;;
    x86_64) SRCDS_RUN=srcds_run_64 SRCDS_BINARY=./srcds_linux64 BIN_SUBDIR=linux64/ TAG_SUFFIX=-x86_64 ELF_CLASS=2 ;;
    *) echo "ARCH must be x86 or x86_64, not $ARCH" >&2; exit 2 ;;
esac

cfg() { jq -er --arg g "$GAME" ".[\$g].$1" "$GAMES_JSON"; }
cfg app_id >/dev/null || { echo "unknown game '$GAME' (see $GAMES_JSON)" >&2; exit 2; }
GAME_DIR=$(cfg game_dir); MAP=$(cfg map); ENGINE=$(cfg sp_engine)
# games.json can ask for the game's bundled libstdc++/libgcc_s to be removed (CS:GO: its
# libgcc_s breaks the image's libstdc++); see the Dockerfile
REMOVE_GAME_LIBSTDCXX=$( [ "$(cfg remove_game_libstdcxx 2>/dev/null)" = true ] && echo 1 || true )
BASE="$SRCDS_IMAGE:$GAME"

echo ">> image $BASE"
[ "${PULL:-1}" = 0 ] || docker pull -q "$BASE" >/dev/null
IMAGE="sp-harness:$GAME$TAG_SUFFIX"
docker build -q -f "$HERE/Dockerfile" --build-arg BASE="$BASE" \
    --build-arg REMOVE_GAME_LIBSTDCXX="$REMOVE_GAME_LIBSTDCXX" \
    --build-arg X86_64="$( [ "$ARCH" = x86_64 ] && echo 1 || true )" -t "$IMAGE" "$HERE" >/dev/null

echo ">> staging Source.Python from $SRC into $OUT"
rm -rf "$OUT"; mkdir -p "$OUT/sp" "$OUT/launcher"
LAUNCHER_GAME=$( [ "$ARCH" = x86_64 ] && cfg x86_64_launcher 2>/dev/null || true )
if [ -n "$LAUNCHER_GAME" ]; then
    # CS:S, DoD:S and HL2DM ship a 64-bit engine and server but no 64-bit launcher
    echo ">> 64-bit launcher from $SRCDS_IMAGE:$LAUNCHER_GAME"
    [ "${PULL:-1}" = 0 ] || docker pull -q "$SRCDS_IMAGE:$LAUNCHER_GAME" >/dev/null
    cid=$(docker create "$SRCDS_IMAGE:$LAUNCHER_GAME")
    mkdir -p "$OUT/launcher/bin/linux64"
    for f in srcds_run_64 srcds_linux64 bin/linux64/libsteam_api.so; do
        docker cp -q "$cid:/srv/srcds/$f" "$OUT/launcher/$f"
    done
    docker rm "$cid" >/dev/null
fi
if [ -d "$SRC" ]; then
    for d in addons cfg logs resource sound; do
        [ -d "$SRC/$d" ] && cp -a "$SRC/$d" "$OUT/sp/"
    done
else
    python3 -I -m zipfile -e "$SRC" "$OUT/sp"
fi
if [ "${OVERLAY_REPO:-}" = 1 ]; then
    REPO=$(git -C "$HERE" rev-parse --show-toplevel)
    echo ">> overlaying working tree of $REPO"
    git -C "$REPO" ls-files -z addons cfg resource sound | (cd "$REPO" && tar -c --null -T -) \
        | tar -x -C "$OUT/sp"
fi
if [ -n "${EXTRA_ADDONS:-}" ]; then
    echo ">> adding $EXTRA_ADDONS"
    cp -a "$EXTRA_ADDONS/." "$OUT/sp/"
fi
CORE="$OUT/sp/addons/source-python/bin/core.so"
[ -f "$CORE" ] || { echo "no addons/source-python/bin/core.so in $SRC" >&2; exit 2; }
# the build must be for the server's architecture (ELF class 1: 32-bit, 2: 64-bit)
[ "$(od -An -tu1 -j4 -N1 "$CORE" | tr -d ' ')" = "$ELF_CLASS" ] \
    || { echo "$CORE isn't an $ARCH build" >&2; exit 2; }
mkdir -p "$OUT/sp/addons/source-python/plugins/sp_harness" "$OUT/sp/cfg"
cp "$HERE/plugin/sp_harness/sp_harness.py" "$OUT/sp/addons/source-python/plugins/sp_harness/"
cat > "$OUT/sp/cfg/sp_harness.cfg" <<'EOF'
sv_hibernate_when_empty 0
sp plugin load sp_harness
EOF
# an update for the loader to apply on start (update.stage2)
[ "${NO_UPDATE:-}" = 1 ] || bash "$HERE/tools/stage_update.sh" "$OUT/sp"

# Dedicated-server builds are server_srv.so; CS:GO ships only server.so.
cid=$(docker create "$BASE")
for SERVER_SO in ${BIN_SUBDIR}server_srv.so ${BIN_SUBDIR}server.so; do
    docker cp -q "$cid:/srv/srcds/$GAME_DIR/bin/$SERVER_SO" "$OUT/server_srv.so" 2>/dev/null && break
done
docker rm "$cid" >/dev/null
echo ">> gamedata vtable check against $GAME_DIR/bin/$SERVER_SO"
set +e
python3 -I "$HERE/tools/vtdump.py" "$OUT/server_srv.so" check \
    "$OUT/sp/addons/source-python/data/source-python/entities" "$ENGINE" "$GAME_DIR" \
    > "$OUT/gamedata-vtables.txt" 2>&1
echo $? > "$OUT/gamedata-vtables.rc"
rm -f "$OUT/server_srv.so"

echo ">> running $GAME_DIR ($ARCH) on $MAP (timeout ${TIMEOUT}s)"
# seccomp=unconfined: Docker's built-in seccomp profile (at least 29.4) refuses socketcall(2)
# with ENOSYS, and 32-bit glibc and srcds create every socket through it, so the server can't
# open its port ("NET_OpenSocket: socket failed: Function not implemented").
docker run --rm --name "sp-harness-$GAME-$$" --security-opt seccomp=unconfined \
    -v "$OUT/sp:/sp:ro" -v "$OUT/launcher:/launcher:ro" -v "$OUT:/out" \
    -e GAME_DIR="$GAME_DIR" -e MAP="$MAP" -e TIMEOUT="$TIMEOUT" -e OWNER="$(id -u):$(id -g)" \
    -e SRCDS_RUN="$SRCDS_RUN" -e SRCDS_BINARY="$SRCDS_BINARY" \
    --entrypoint bash "$IMAGE" -c '
        cp -a /sp/. "/srv/srcds/$GAME_DIR/"
        cp -a /launcher/. /srv/srcds/
        cd /srv/srcds
        timeout -k 10 "$TIMEOUT" "./$SRCDS_RUN" -binary /usr/local/bin/srcds-gdb \
            -game "$GAME_DIR" -condebug -norestart \
            -insecure -nohltv +sv_lan 1 +sv_hibernate_when_empty 0 +maxplayers 8 \
            +map "$MAP" +exec sp_harness.cfg > /out/srcds_run.log 2>&1
        echo $? > /out/srcds.rc
        cp "$GAME_DIR/console.log" /out/console.log 2>/dev/null
        cp "$GAME_DIR/logs/sp_harness.json" /out/results.json 2>/dev/null
        cp -r "$GAME_DIR/logs/source-python" /out/source-python-logs 2>/dev/null
        chown -R "$OWNER" /out'
set -e

python3 -I "$HERE/tools/report.py" "$OUT"
