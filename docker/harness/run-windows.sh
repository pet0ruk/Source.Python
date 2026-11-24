#!/usr/bin/env bash
# Run Source.Python's functional tests on a Windows dedicated server: the Windows counterpart of
# run.sh, for Git Bash on Windows (CI: windows-latest). Needs git, Python 3 and network access.
#
#   docker/harness/run-windows.sh <game> <source-python release .zip | extracted dir> [out-dir]
#
#   <game>     a key of docker/srcds/games.json (tf2, css, dods, hl2dm, l4d2, csgo, bms)
#   out-dir    default ./sp-harness-out/<game>-windows; receives results.json, console.log,
#              srcds_run.log and Source.Python's logs
#
# Env:
#   SRCDS_IMAGE     image repository (default ghcr.io/pet0ruk/srcds); the tag is <game>-windows,
#                   a files-only image with the Windows server (see docker/srcds/Dockerfile)
#   SERVER_DIR      where to put the server (default <out>/server); reused if it already has
#                   srcds.exe, otherwise extracted from the image (tools/oci_extract.py)
#   GAMES_JSON      per-game settings (default docker/srcds/games.json)
#   TIMEOUT         seconds before the server is killed (default 240)
#   OVERLAY_REPO=1  copy this repository's tracked addons/cfg/resource/sound files over the
#                   release, as in run.sh
#   NO_UPDATE=1     don't stage an update for the loader to apply on start, as in run.sh
#   CRASH_DUMPS=1   have Windows Error Reporting write a minidump of srcds.exe if it crashes
#                   (into <out>/dumps; sets HKLM registry values, so it needs admin rights: CI),
#                   and analyse it with cdb.exe, if installed, into <out>/crash.txt
#
# The offline gamedata vtable check (run.sh) needs the symbols of the Linux server binary, so it
# is reported as skipped; this run is what exercises the Windows offsets and signatures.
# Exit status: 0 if every check passed (skips are allowed), 1 otherwise.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
GAMES_JSON=${GAMES_JSON:-$(cd "$HERE/../srcds" && pwd)/games.json}
GAME=${1:?usage: run-windows.sh <game> <source-python.zip|dir> [out-dir]}
SRC=$(realpath "${2:?source-python release zip or directory}")
OUT=$(realpath -m "${3:-$PWD/sp-harness-out/$GAME-windows}")
SRCDS_IMAGE=${SRCDS_IMAGE:-ghcr.io/pet0ruk/srcds}
SERVER_DIR=$(realpath -m "${SERVER_DIR:-$OUT/server}")
TIMEOUT=${TIMEOUT:-240}
PYTHON=$(command -v python3 || command -v python)

cfg() { "$PYTHON" -I -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]][sys.argv[3]])' \
            "$GAMES_JSON" "$GAME" "$1"; }
cfg app_id >/dev/null 2>&1 || { echo "unknown game '$GAME' (see $GAMES_JSON)" >&2; exit 2; }
GAME_DIR=$(cfg game_dir); MAP=$(cfg map)

if [ ! -f "$SERVER_DIR/srcds.exe" ]; then
    echo ">> extracting $SRCDS_IMAGE:$GAME-windows into $SERVER_DIR"
    rm -rf "$SERVER_DIR"
    "$PYTHON" -I "$HERE/tools/oci_extract.py" "$SRCDS_IMAGE:$GAME-windows" "$SERVER_DIR" srv/srcds
fi
G=$SERVER_DIR/$GAME_DIR

echo ">> installing Source.Python from $SRC into $G"
mkdir -p "$OUT"
rm -rf "$OUT/results.json" "$OUT/console.log" "$OUT/srcds_run.log" "$OUT/source-python-logs"
rm -rf "$G/addons/source-python" "$G/addons/source-python.dll" "$G/addons/source-python.vdf" \
       "$G/logs/sp_harness.json" "$G/logs/source-python" "$G/console.log"
if [ -d "$SRC" ]; then
    for d in addons cfg logs resource sound; do
        [ -d "$SRC/$d" ] && cp -r "$SRC/$d" "$G/"
    done
else
    "$PYTHON" -I -m zipfile -e "$SRC" "$G"
fi
if [ "${OVERLAY_REPO:-}" = 1 ]; then
    REPO=$(git -C "$HERE" rev-parse --show-toplevel)
    echo ">> overlaying working tree of $REPO"
    git -C "$REPO" ls-files -z addons cfg resource sound | (cd "$REPO" && tar -c --null -T -) \
        | tar -x -C "$G"
fi
[ -f "$G/addons/source-python/bin/core.dll" ] || { echo "no addons/source-python/bin/core.dll in $SRC" >&2; exit 2; }
mkdir -p "$G/addons/source-python/plugins/sp_harness" "$G/cfg"
cp "$HERE/plugin/sp_harness/sp_harness.py" "$G/addons/source-python/plugins/sp_harness/"
printf 'sv_hibernate_when_empty 0\nsp plugin load sp_harness\n' > "$G/cfg/sp_harness.cfg"
# an update for the loader to apply on start (update.stage2), as in run.sh
[ "${NO_UPDATE:-}" = 1 ] || bash "$HERE/tools/stage_update.sh" "$G"

echo 'not available on Windows (server.dll has no symbols)' > "$OUT/gamedata-vtables.txt"
echo skip > "$OUT/gamedata-vtables.rc"

echo ">> running $GAME_DIR on $MAP (timeout ${TIMEOUT}s)"
# srcds.exe -console needs a real console as its input ("CTextConsoleWin32::GetLine:
# !GetNumberOfConsoleInputEvents" otherwise, then it hangs), so it gets a console of its own via
# Start-Process instead of Git Bash's pipes; its output goes to console.log (-condebug), which is
# also copied to srcds_run.log. On a timeout the process tree is killed and the exit code is 124.
set +e
SERVER_WIN=$(cygpath -w "$SERVER_DIR")
OUT_WIN=$(cygpath -w "$OUT")
rm -rf "$OUT/dumps" "$OUT/crash.txt" "$OUT/srcds.exitcode"
if [ "${CRASH_DUMPS:-}" = 1 ]; then
    mkdir -p "$OUT/dumps"
    powershell.exe -NoProfile -NonInteractive -Command "
        \$wer = 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting'
        New-Item -Force -Path \"\$wer\LocalDumps\srcds.exe\" | Out-Null
        Set-ItemProperty -Path \"\$wer\LocalDumps\srcds.exe\" -Name DumpFolder -Type ExpandString -Value '$OUT_WIN\dumps'
        Set-ItemProperty -Path \"\$wer\LocalDumps\srcds.exe\" -Name DumpType -Type DWord -Value 1
        Set-ItemProperty -Path \"\$wer\LocalDumps\srcds.exe\" -Name DumpCount -Type DWord -Value 3
        Set-ItemProperty -Path \$wer -Name DontShowUI -Type DWord -Value 1" \
        || echo ">> could not enable crash dumps (needs admin rights)"
fi
ARGS="-console -game $GAME_DIR -condebug -norestart -insecure -nohltv +sv_lan 1 +sv_hibernate_when_empty 0 +maxplayers 8 +map $MAP +exec sp_harness.cfg"
powershell.exe -NoProfile -NonInteractive -Command "
    \$p = Start-Process -FilePath (Join-Path '$SERVER_WIN' 'srcds.exe') -WorkingDirectory '$SERVER_WIN' \
         -ArgumentList '$ARGS' -PassThru
    if (-not \$p.WaitForExit(${TIMEOUT}000)) {
        & taskkill.exe /T /F /PID \$p.Id | Out-Null
        exit 124
    }
    # the full exit code (Git Bash keeps only its low 8 bits): e.g. 0xC0000005 for a crash
    Set-Content -Path '$OUT_WIN\srcds.exitcode' -Value ('0x{0:X8}' -f \$p.ExitCode)
    exit \$p.ExitCode" > "$OUT/powershell.log" 2>&1
echo $? > "$OUT/srcds.rc"
# a crash dump, if Windows wrote one (it may appear shortly after the process has gone): the
# crashing stack (and all threads') with cdb
dump=""
if [ "${CRASH_DUMPS:-}" = 1 ] && [ "$(cat "$OUT/srcds.rc")" != 0 ]; then
    for _ in $(seq 1 20); do
        dump=$(ls "$OUT"/dumps/*.dmp 2>/dev/null | head -1)
        [ -z "$dump" ] || break
        sleep 1
    done
fi
if [ -n "$dump" ]; then
    cdb=""
    for c in "/c/Program Files (x86)/Windows Kits/10/Debuggers/x86/cdb.exe" \
             "/c/Program Files/Windows Kits/10/Debuggers/x86/cdb.exe"; do
        [ -x "$c" ] && cdb=$c && break
    done
    if [ -n "$cdb" ]; then
        {   echo "==== srcds crashed (exit code $(cat "$OUT/srcds.exitcode" 2>/dev/null)): $(basename "$dump") ===="
            "$cdb" -z "$(cygpath -w "$dump")" -y "srv*$(cygpath -w "$OUT")\\symbols*https://msdl.microsoft.com/download/symbols" \
                -c ".ecxr; .echo ==== crashing thread ====; kv 50; .echo ==== all threads ====; ~*kb 25; .echo ==== modules ====; lm; q" 2>&1
        } > "$OUT/crash.txt"
    else
        echo "==== srcds crashed: $(basename "$dump") (no cdb.exe to analyse it) ====" > "$OUT/crash.txt"
    fi
fi
cp "$G/console.log" "$OUT/console.log" 2>/dev/null
cp "$G/console.log" "$OUT/srcds_run.log" 2>/dev/null
cat "$OUT/powershell.log" >> "$OUT/srcds_run.log" 2>/dev/null
cp "$G/logs/sp_harness.json" "$OUT/results.json" 2>/dev/null
cp -r "$G/logs/source-python" "$OUT/source-python-logs" 2>/dev/null
set -e

"$PYTHON" -I "$HERE/tools/report.py" "$OUT"
