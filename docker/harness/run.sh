#!/usr/bin/env bash
# Run Source.Python's functional tests against a srcds test image (see docker/srcds).
#
#   docker/harness/run.sh <game> <source-python release .zip | extracted dir> [out-dir]
#
#   <game>     a key of docker/srcds/games.json (tf2, css, dods, hl2dm, l4d2)
#   out-dir    default ./sp-harness-out/<game>; receives results.json, console.log,
#              Source.Python's logs and the gamedata check output
#
# Env:
#   SRCDS_IMAGE     image repository (default ghcr.io/pet0ruk/srcds); the tag is <game>
#   GAMES_JSON      per-game settings (default docker/srcds/games.json), e.g. for a game
#                   without a published image
#   PULL=0          don't pull the image first
#   RUNTIME=bare    run on the srcds image as-is, without the libraries Source.Python's bundled
#                   Python needs (docker/harness/Dockerfile); useful for testing builds that
#                   ship their own
#   REMOVE_GAME_LIBSTDCXX=1  remove the game's bundled libstdc++/libgcc_s (L4D2), which older
#                   releases need to load (current ones link libstdc++ statically)
#   KEEP_EXECSTACK=1  don't clear the executable-stack flag on core.so (glibc >= 2.41, as in
#                   the images, then refuses to load it)
#   TIMEOUT         seconds before the server is killed (default 240)
#   OVERLAY_REPO=1  copy this repository's tracked addons/cfg/resource/sound files (as they are
#                   in the working tree) over the release, to test Python/data changes against
#                   prebuilt binaries without rebuilding
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

cfg() { jq -er --arg g "$GAME" ".[\$g].$1" "$GAMES_JSON"; }
cfg app_id >/dev/null || { echo "unknown game '$GAME' (see $GAMES_JSON)" >&2; exit 2; }
GAME_DIR=$(cfg game_dir); MAP=$(cfg map); ENGINE=$(cfg sp_engine)
BASE="$SRCDS_IMAGE:$GAME"

echo ">> image $BASE"
[ "${PULL:-1}" = 0 ] || docker pull -q "$BASE" >/dev/null
IMAGE=$BASE
if [ "${RUNTIME:-}" != bare ]; then
    IMAGE="sp-harness:$GAME"
    docker build -q -f "$HERE/Dockerfile" --build-arg BASE="$BASE" \
        --build-arg REMOVE_GAME_LIBSTDCXX="${REMOVE_GAME_LIBSTDCXX:-}" -t "$IMAGE" "$HERE" >/dev/null
fi

echo ">> staging Source.Python from $SRC into $OUT"
rm -rf "$OUT"; mkdir -p "$OUT/sp"
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
CORE="$OUT/sp/addons/source-python/bin/core.so"
[ -f "$CORE" ] || { echo "no addons/source-python/bin/core.so in $SRC" >&2; exit 2; }
mkdir -p "$OUT/sp/addons/source-python/plugins/sp_harness" "$OUT/sp/cfg"
cp "$HERE/plugin/sp_harness/sp_harness.py" "$OUT/sp/addons/source-python/plugins/sp_harness/"
cat > "$OUT/sp/cfg/sp_harness.cfg" <<'EOF'
sv_hibernate_when_empty 0
sp plugin load sp_harness
EOF
if [ "${KEEP_EXECSTACK:-}" != 1 ]; then
    python3 -I "$HERE/tools/clear_execstack.py" "$CORE"
fi

# Dedicated-server builds are server_srv.so; CS:GO ships only server.so.
cid=$(docker create "$BASE")
for SERVER_SO in server_srv.so server.so; do
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

echo ">> running $GAME_DIR on $MAP (timeout ${TIMEOUT}s)"
# seccomp=unconfined: Docker's built-in seccomp profile (at least 29.4) refuses socketcall(2)
# with ENOSYS, and 32-bit glibc and srcds create every socket through it, so the server can't
# open its port ("NET_OpenSocket: socket failed: Function not implemented").
docker run --rm --name "sp-harness-$GAME-$$" --security-opt seccomp=unconfined \
    -v "$OUT/sp:/sp:ro" -v "$OUT:/out" \
    -e GAME_DIR="$GAME_DIR" -e MAP="$MAP" -e TIMEOUT="$TIMEOUT" -e OWNER="$(id -u):$(id -g)" \
    --entrypoint bash "$IMAGE" -c '
        cp -a /sp/. "/srv/srcds/$GAME_DIR/"
        cd /srv/srcds
        timeout -k 10 "$TIMEOUT" ./srcds_run -game "$GAME_DIR" -condebug -norestart \
            -insecure -nohltv +sv_lan 1 +sv_hibernate_when_empty 0 +maxplayers 8 \
            +map "$MAP" +exec sp_harness.cfg > /out/srcds_run.log 2>&1
        echo $? > /out/srcds.rc
        cp "$GAME_DIR/console.log" /out/console.log 2>/dev/null
        cp "$GAME_DIR/logs/sp_harness.json" /out/results.json 2>/dev/null
        cp -r "$GAME_DIR/logs/source-python" /out/source-python-logs 2>/dev/null
        chown -R "$OWNER" /out'
set -e

python3 -I "$HERE/tools/report.py" "$OUT"
