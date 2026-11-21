#!/usr/bin/env bash
# Decide which srcds test images need building.
#
# For each selected game in games.json: ask Steam (ISteamApps/UpToDateCheck) for the version
# servers must run, read the steam.required_version label of <image>:<game> with skopeo, and
# select the game when they differ, the image doesn't exist / can't be read, or FORCE=true.
#
# Env:  GAME      "all" or a key of games.json (default all)
#       FORCE     "true" to select every requested game without checking (default false)
#       OWNER     registry namespace, e.g. the GitHub repository owner (required)
#       REGISTRY  default ghcr.io
#       IMAGE     image name under OWNER (default srcds)
#       STAMP     build stamp for the dated tag (default: UTC now, YYYYMMDD-HHMMSS)
#       SKOPEO    skopeo command (default "skopeo"; e.g. "docker run --rm quay.io/skopeo/stable")
#       REGISTRY_USER / REGISTRY_PASSWORD  optional credentials for skopeo
# Out:  matrix=<JSON array of {game, app_id, game_dir, map, windows_first, verify_version,
#       version, image, stamp, tags}> and count=<n> in $GITHUB_OUTPUT (or stdout); a table in
#       $GITHUB_STEP_SUMMARY when set. Each image is tagged <image>:<game> (moving, what the
#       version check reads) and <image>:<game>-<STAMP> (lets the build job find and delete the
#       previous image for that game).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
GAMES_JSON="$HERE/games.json"
GAME=${GAME:-all}; FORCE=${FORCE:-false}
: "${OWNER:?}"
REGISTRY=${REGISTRY:-ghcr.io}; IMAGE=${IMAGE:-srcds}; SKOPEO=${SKOPEO:-skopeo}
STAMP=${STAMP:-$(date -u +%Y%m%d-%H%M%S)}
owner=$(printf '%s' "$OWNER" | tr '[:upper:]' '[:lower:]')

if [ "$GAME" = all ]; then
    games=$(jq -r 'keys_unsorted[]' "$GAMES_JSON")
else
    jq -e --arg g "$GAME" 'has($g)' "$GAMES_JSON" >/dev/null \
        || { echo "unknown game '$GAME'" >&2; exit 1; }
    games=$GAME
fi

creds=()
if [ -n "${REGISTRY_USER:-}" ] && [ -n "${REGISTRY_PASSWORD:-}" ]; then
    creds=(--creds "$REGISTRY_USER:$REGISTRY_PASSWORD")
fi

matrix='[]'
summary="| game | Steam version | image version | action |\n|---|---|---|---|\n"
for g in $games; do
    cfg() { jq -r --arg g "$g" ".[\$g].$1 // empty" "$GAMES_JSON"; }
    image="$REGISTRY/$owner/$IMAGE"

    version=""
    version_app_id=$(cfg version_app_id)
    if [ -n "$version_app_id" ]; then
        version=$(curl -fsS --retry 5 --retry-all-errors \
            "https://api.steampowered.com/ISteamApps/UpToDateCheck/v1?appid=$version_app_id&version=0" \
            | jq -er '.response.required_version') \
            || { echo "!! could not get Steam version for $g" >&2; exit 1; }
    fi

    current=""
    if labels=$($SKOPEO inspect --no-tags "${creds[@]}" "docker://$image:$g" 2>/dev/null); then
        current=$(jq -r '.Labels["steam.required_version"] // empty' <<<"$labels")
    fi

    if [ "$FORCE" = true ]; then
        action="build (forced)"
    elif [ -z "$current" ]; then
        action="build (no image / no label)"
    elif [ -z "$version" ] || [ "$version" != "$current" ]; then
        action="build (outdated)"
    else
        action="up to date"
    fi
    summary+="| $g | ${version:-n/a} | ${current:-none} | $action |\n"
    echo ">> $g: steam=${version:-n/a} image=${current:-none} -> $action" >&2
    [ "$action" = "up to date" ] && continue

    tags="$image:$g,$image:$g-$STAMP"
    matrix=$(jq -c \
        --arg game "$g" --arg app_id "$(cfg app_id)" --arg game_dir "$(cfg game_dir)" \
        --arg map "$(cfg map)" --arg version "$version" --arg image "$image" --arg tags "$tags" \
        --arg stamp "$STAMP" \
        --arg windows_first "$( [ "$(cfg windows_first)" = true ] && echo 1 || true )" \
        --arg verify_version "$( [ "$(cfg verify_version)" = false ] && echo 0 || echo 1 )" \
        '. + [{game: $game, app_id: $app_id, game_dir: $game_dir, map: $map,
               windows_first: $windows_first, verify_version: $verify_version,
               version: $version, image: $image, stamp: $stamp, tags: $tags}]' <<<"$matrix")
done

out=${GITHUB_OUTPUT:-/dev/stdout}
{ echo "matrix=$matrix"; echo "count=$(jq length <<<"$matrix")"; } >> "$out"
[ -z "${GITHUB_STEP_SUMMARY:-}" ] || printf '%b' "$summary" >> "$GITHUB_STEP_SUMMARY"
