#!/usr/bin/env bash
# Download a Source dedicated server with steamcmd and strip it down to a single map.
# Runs inside the "download" stage of docker/srcds/Dockerfile.
#
# Env: APP_ID (server app), GAME_DIR (mod dir, e.g. tf), KEEP_MAP (map to keep, no extension),
#      PLATFORM (linux (default) or windows: which server build steamcmd downloads),
#      REQUIRED_VERSION (optional; if set, must equal the version in <GAME_DIR>/steam.inf
#      unless VERIFY_VERSION=0), WINDOWS_FIRST (1 = install as Windows first, for L4D2's
#      Linux build; ignored for PLATFORM=windows),
#      VPK_STRIP (optional; "<path>_dir.vpk:<ext>,<ext>,...": unpack that VPK as loose files
#      without those extensions and delete it, see vpk_strip.py), PRUNE (optional;
#      space-separated globs, relative to the install, of files/directories to delete).
set -euo pipefail
: "${APP_ID:?}" "${GAME_DIR:?}" "${KEEP_MAP:?}"
PLATFORM=${PLATFORM:-linux}
case "$PLATFORM" in
    linux|windows) ;;
    *) echo "!! PLATFORM must be linux or windows, not '$PLATFORM'" >&2; exit 1 ;;
esac
DIR=/srv/srcds
MANIFEST="$DIR/steamapps/appmanifest_$APP_ID.acf"

# A fresh steamcmd's first run updates itself and then fails ("Missing configuration").
steamcmd +login anonymous +quit >/dev/null 2>&1 || true

# L4D2's Linux depots fail with "Invalid platform" on a fresh install unless the app is first
# installed with the platform forced to Windows (then updated/validated as Linux below).
if [ "$PLATFORM" = linux ] && [ "${WINDOWS_FIRST:-}" = 1 ]; then
    steamcmd +@sSteamCmdForcePlatformType windows +force_install_dir "$DIR" +login anonymous \
        +app_update "$APP_ID" +quit || true
fi

# steamcmd's exit status is unreliable, so retry until the manifest says "fully installed" (4).
for attempt in 1 2 3 4 5; do
    steamcmd +@sSteamCmdForcePlatformType "$PLATFORM" +force_install_dir "$DIR" +login anonymous \
        +app_update "$APP_ID" validate +quit || true
    if grep -Eq '"StateFlags"[[:space:]]+"4"' "$MANIFEST" 2>/dev/null; then
        break
    fi
    if [ "$attempt" = 5 ]; then
        echo "!! steamcmd did not finish installing app $APP_ID" >&2
        exit 1
    fi
    echo ">> steamcmd attempt $attempt incomplete, retrying"
    sleep 15
done

BUILD_ID=$(sed -nE 's/^[[:space:]]*"buildid"[[:space:]]+"([0-9]+)".*/\1/p' "$MANIFEST" | head -1)
echo ">> installed app $APP_ID ($PLATFORM) buildid $BUILD_ID: $(du -sh "$DIR" | cut -f1)"

# Keep only $KEEP_MAP.* in every top-level */maps dir (subdirectories such as graphs/ or
# soundcache/ are left alone). Maps that live inside VPKs are unaffected.
shopt -s nullglob
for maps in "$DIR"/*/maps; do
    find "$maps" -maxdepth 1 -type f ! -name "$KEEP_MAP.*" -delete
done
if ! [ -f "$DIR/$GAME_DIR/maps/$KEEP_MAP.bsp" ]; then
    echo ">> note: $GAME_DIR/maps/$KEEP_MAP.bsp not present as a loose file (packed in a VPK?)"
fi

# Client content a dedicated server doesn't load (textures, audio, UI), for games whose server
# ships it (games.json: vpk_strip, prune).
if [ -n "${VPK_STRIP:-}" ]; then
    python3 -I /usr/local/bin/vpk_strip.py "$DIR/${VPK_STRIP%%:*}" "${VPK_STRIP#*:}"
fi
# split PRUNE into patterns without expanding them here (nullglob would drop any that match
# nothing in the current directory); each is expanded under $DIR
set -f; read -ra patterns <<<"${PRUNE:-}"; set +f
for pattern in "${patterns[@]}"; do
    case "$pattern" in /*|*..*) echo "!! PRUNE pattern '$pattern' must be relative" >&2; exit 1 ;; esac
    # shellcheck disable=SC2086  # the pattern is a glob
    matches=("$DIR"/$pattern)
    [ "${#matches[@]}" -gt 0 ] || { echo "!! PRUNE pattern '$pattern' matches nothing" >&2; exit 1; }
    echo ">> pruning $pattern (${#matches[@]})"
    rm -rf "${matches[@]}"
done

# Steam bookkeeping that isn't needed to run the server.
rm -rf "$DIR/steamapps/downloading" "$DIR/steamapps/temp" "$DIR/steamapps/shadercache"

# Version as the engine reports it (what ISteamApps/UpToDateCheck compares against).
INF="$DIR/$GAME_DIR/steam.inf"
VERSION=""
if [ -f "$INF" ]; then
    VERSION=$(sed -nE 's/^ServerVersion=([0-9]+).*/\1/p' "$INF" | head -1)
    if [ -z "$VERSION" ]; then  # e.g. L4D2: PatchVersion=2.2.4.3 -> 2243
        VERSION=$(sed -nE 's/^PatchVersion=([0-9.]+).*/\1/p' "$INF" | head -1 | tr -d .)
    fi
fi
echo ">> steam.inf ($INF):"; sed 's/^/     /' "$INF" 2>/dev/null || true
echo ">> steam.inf version: ${VERSION:-unknown}; after pruning: $(du -sh "$DIR" | cut -f1)"

# VERIFY_VERSION=0 skips this for games whose steam.inf doesn't carry Steam's required_version.
if [ "${VERIFY_VERSION:-1}" != 0 ] && [ -n "${REQUIRED_VERSION:-}" ] \
        && [ "$VERSION" != "$REQUIRED_VERSION" ]; then
    echo "!! downloaded version '$VERSION' != required version '$REQUIRED_VERSION'" >&2
    exit 1
fi

printf 'APP_ID=%s\nPLATFORM=%s\nBUILD_ID=%s\nVERSION=%s\nMAP=%s\n' \
    "$APP_ID" "$PLATFORM" "$BUILD_ID" "$VERSION" "$KEEP_MAP" > "$DIR/.srcds-image"
