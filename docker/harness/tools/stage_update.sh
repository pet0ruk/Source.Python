#!/bin/bash
# Stages a Source.Python update in an installed game directory, so the loader applies update
# stage 2 when the server starts (src/loader/updater.cpp): it deletes packages/source-python,
# packages/site-packages, data/source-python, docs/source-python and Python3, then moves the
# contents of addons/source-python/update/ into the game directory and deletes it.
#
#   stage_update.sh <game dir>
#
# The update is a copy of what is installed, plus a marker file in data/source-python that only
# the update has. The harness checks that the marker arrived and update/ is gone
# (update.stage2); if stage 2 went wrong, Source.Python doesn't start at all.
set -euo pipefail
G=${1:?usage: stage_update.sh <game dir>}
A=$G/addons/source-python
U=$A/update/addons/source-python
rm -rf "$A/update"
mkdir -p "$U/packages" "$U/data" "$U/docs"
cp -r "$A/packages/source-python" "$A/packages/site-packages" "$U/packages/"
cp -r "$A/data/source-python" "$U/data/"
[ ! -d "$A/docs/source-python" ] || cp -r "$A/docs/source-python" "$U/docs/"
cp -r "$A/Python3" "$U/"
echo 'staged by docker/harness/tools/stage_update.sh' > "$U/data/source-python/sp_harness_update.txt"
