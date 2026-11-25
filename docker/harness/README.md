# Source.Python test harness

Functional tests for a Source.Python release, run inside a real dedicated server: a headless
srcds from the `srcds:<game>` test images (built by `.github/workflows/srcds-images.yml` from
`docker/srcds/`), with bots standing in for players.

```bash
docker/harness/run.sh tf2 source-python-tf2.zip            # results in ./sp-harness-out/tf2
docker/harness/run.sh css path/to/extracted-release out/css
OVERLAY_REPO=1 docker/harness/run.sh dods release.zip       # test working-tree Python/data
```

Games: the keys of `docker/srcds/games.json` (tf2, css, dods, hl2dm, l4d2, csgo, bms). The release must be
for the same game (each Linux build targets one engine branch). Exit status is 0 only if every
check passed; skips and known issues don't fail a run. Needs Docker, `jq` and Python 3.

## What a run does

1. Pulls `ghcr.io/pet0ruk/srcds:<game>` and builds `sp-harness:<game>` on top of it
   (`Dockerfile`): the server as shipped, except for a game's bundled `libstdc++`/`libgcc_s`
   when `games.json` asks for it (`remove_game_libstdcxx`: CS:GO). Nothing is added for
   Source.Python: it links libstdc++ statically and its Python runtime brings its own
   libraries, so a run also shows the release needs nothing from the system.
2. Stages the release (zip or directory) into `<out>/sp`, optionally overlays the repository
   (`OVERLAY_REPO=1`) and adds the `sp_harness` plugin.
3. Offline gamedata check: `tools/vtdump.py` compares every `[virtual_function]` entry that has a
   mangled-name comment with the vtables in the image's `server_srv.so`, using the same
   engine/game merge order as `GameConfigObj`.
4. Starts the server on the game's test map with `sp plugin load sp_harness`, with seccomp off
   (Docker 29.4's default profile blocks the 32-bit `socketcall` that srcds needs). The plugin
   (`plugin/sp_harness/sp_harness.py`) runs the checks, writes `logs/sp_harness.json` after every
   check, adds bots, runs the player checks, changes level (`changelevel` to the same map),
   runs the checks that need a new level and quits. The loader first applies an update the
   script staged (`tools/stage_update.sh`, `NO_UPDATE=1` to skip).
5. `tools/report.py` prints the results. If the server crashed, the report names the check that
   was running.

## Checks

| Area | Checks |
|---|---|
| runtime | Python version, platform, engine constants, native stdlib modules (ssl, ctypes, sqlite3, lzma, bz2, uuid, ...), compiled site-packages (greenlet, psycopg2) |
| engine / entities | map, max clients, worldspawn, create/spawn/remove, `set_model`, `teleport` |
| filters | `EntityIter` (networked), `BaseEntityIter` (server-only entities) |
| memory | every `[function]` identifier for this platform in the effective gamedata resolves (`find_binary`; symbols and byte signatures), `make_function`, vtable read through `Pointer` matches the binary and the gamedata `teleport` slot (the last two need symbols: Linux only, not CS:GO), a `Callback` with BOOL arguments and return value (upstream #419) |
| update | the loader applied the staged update (update stage 2) |
| cvars / keyvalues / commands | `ConVar` create/set/get; values set from the server console are what `ConVar` reads and what `OnConVarChanged` gets (old and new); `KeyValues` round trip; `ServerCommand`; `ClientCommand` (a bot made to run a command server-side, with its index and arguments) |
| stringtables / precache / effects | `Downloadables` adds to the engine's downloadables table, and again on the next level; `Model` precache; `TempEntity('BeamPoints')` properties |
| players (bots) | properties agree with the game's `IPlayerInfo` (name, userid, health, team, origin); helpers (userid/index/playerinfo/inthandle); `teleport`; `take_damage` lowers health and reaches the hook; messages; menus |
| level change | `changelevel` to the same map: one `OnLevelEnd` and one `OnLevelInit` for that map, at least one `OnLevelShutdown` (some games call it twice) |
| counts | entity pre/post hooks (`pre_think`, `post_think`, `run_command`, `on_take_damage`), `Event` and `PreEvent`, `OnTick`, `OnClientActive`, `OnConVarChanged`, `OnLevelShutdown`, `OnLevelInit`, `ServerCommand`; exactly one `Delay` and three `Repeat` calls |
| events | `event['userid']`, `event.variables.get_int()` and `.as_dict()` agree with `event.get_int()` (upstream issue #536); a `CustomEvent` (loaded once from a `.res` file) fired before and after the level change arrives with its values |

Where possible a check observes the effect through a different path than the one that caused
it: the engine's own interfaces (`IPlayerInfo`, the server console, string tables) or engine
dispatch (hooks, events, commands), not a read back through the same Source.Python code. A few
can only show that the call didn't fail, because only a real game client could see the result:
messages, menus and temp entities sent to bots (fake clients receive nothing), and anything that
needs a client to answer (`OnQueryCvarValueFinished`, menu selections).

Known issues are reported as `XFAIL` (and `XPASS` once they start passing); there are none at
the moment.

## 64-bit servers

`ARCH=x86_64` runs the game's 64-bit server (`srcds_run_64`, `bin/linux64`) with a 64-bit build
(`ARCH=x86_64 docker/build/build.sh`), for the games marked `"x86_64": true` in
`docker/srcds/games.json` (TF2 so far; CS:S, DoD:S and HL2DM ship the 64-bit engine but no 64-bit
launcher). The test image then also gets the 64-bit `libcurl-gnutls` the engine needs, and the
vtable check reads the 64-bit `server_srv.so`. The CI job is `test-x86_64`.

```bash
ARCH=x86_64 docker/build/build.sh tf2 out/tf2-x86_64
ARCH=x86_64 docker/harness/run.sh tf2 out/tf2-x86_64/release
```

## Windows

`run-windows.sh` is the same run for the Windows server, in Git Bash on Windows (the CI job
`test-windows`). It extracts the files of the files-only image `srcds:<game>-windows` with
`tools/oci_extract.py` (no Docker needed), installs the release (built by
`docker/build/build-windows.sh`) and runs `srcds.exe -console` with the same plugin. The offline
vtable check is skipped (server.dll has no symbols), so this run is what exercises the Windows
offsets and signatures.

```bash
docker/build/build-windows.sh tf2 out/tf2-win
docker/harness/run-windows.sh tf2 out/tf2-win/release
```

## Per-game notes

Bot setup lives in `GAMES` at the top of the plugin. TF2, CS:S and HL2DM remove bots on a
server without humans unless `*_bot_join_after_player 0` is set; DoD:S's `bot` needs
`sv_cheats 1`; HL2DM's bots are `hl2mp_bot_add` (NextBot, since the 2025 update).

CS:GO: the test image has the server without the client content its install ships (textures,
audio, UI images; see `vpk_strip` and `prune` in `docker/srcds/games.json`), 4.4 GB instead of
28 GB. Its bundled `libgcc_s` is removed (`remove_game_libstdcxx`), as the engine can't load
with it next to the image's newer `libstdc++`. Bots are immune to damage for a while after
spawning in warmup, so `players.take_damage` clears that first. The Linux server binary is
stripped, so the symbol checks are skipped.

## Files

- `run.sh` — runner; see the header for environment variables (`ARCH`, `SRCDS_IMAGE`, `PULL`,
  `GAMES_JSON`, `TIMEOUT`, `OVERLAY_REPO`, `NO_UPDATE`, `EXTRA_ADDONS`)
- `Dockerfile` — the test image on top of `srcds:<game>`
- `plugin/sp_harness/sp_harness.py` — the in-server checks
- `tools/vtdump.py` — vtable dump / gamedata check for 32-bit and x86-64 ELF binaries
  (`vtdump.py <server_srv.so> dump <Class>`)
- `run-windows.sh` — the Windows runner (see above)
- `tools/oci_extract.py` — extract a public image's files without Docker
- `tools/report.py`
