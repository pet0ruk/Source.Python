# Source.Python test harness

Functional tests for a Source.Python release, run inside a real dedicated server: a headless
srcds from the `srcds:<game>` test images (built by `.github/workflows/srcds-images.yml` from
`docker/srcds/`), with bots standing in for players.

```bash
docker/harness/run.sh tf2 source-python-tf2.zip            # results in ./sp-harness-out/tf2
docker/harness/run.sh css path/to/extracted-release out/css
OVERLAY_REPO=1 docker/harness/run.sh dods release.zip       # test working-tree Python/data
```

Games: the keys of `docker/srcds/games.json` (tf2, css, dods, hl2dm, l4d2). The release must be
for the same game (each Linux build targets one engine branch). Exit status is 0 only if every
check passed; skips and known issues don't fail a run. Needs Docker, `jq` and Python 3.

## What a run does

1. Pulls `ghcr.io/pet0ruk/srcds:<game>` and builds `sp-harness:<game>` on top of it
   (`Dockerfile`): adds the system libraries the Python bundled with older releases (v743 and
   earlier) links against (libffi 7 and OpenSSL 1.1 from Ubuntu 20.04, libbz2/liblzma/libuuid/libpq
   from Debian). With `REMOVE_GAME_LIBSTDCXX=1` it also removes L4D2's bundled
   `libstdc++`/`libgcc_s`, which those older releases need; current builds link libstdc++
   statically and run against the game as shipped.
2. Stages the release (zip or directory) into `<out>/sp`, optionally overlays the repository
   (`OVERLAY_REPO=1`), adds the `sp_harness` plugin and clears the executable-stack flag on
   `core.so` (`tools/clear_execstack.py`; glibc >= 2.41 refuses to load it otherwise, set
   `KEEP_EXECSTACK=1` to test as shipped).
3. Offline gamedata check: `tools/vtdump.py` compares every `[virtual_function]` entry that has a
   mangled-name comment with the vtables in the image's `server_srv.so`, using the same
   engine/game merge order as `GameConfigObj`.
4. Starts the server on the game's test map with `sp plugin load sp_harness`, with seccomp off
   (Docker 29.4's default profile blocks the 32-bit `socketcall` that srcds needs). The plugin
   (`plugin/sp_harness/sp_harness.py`) runs the checks, writes `logs/sp_harness.json` after every
   check, adds bots, runs the player checks and quits.
5. `tools/report.py` prints the results. If the server crashed, the report names the check that
   was running.

## Checks

| Area | Checks |
|---|---|
| runtime | Python version, platform, engine constants, native stdlib modules (ssl, ctypes, sqlite3, lzma, bz2, uuid, ...), compiled site-packages (greenlet, psycopg2) |
| engine / entities | map, max clients, worldspawn, create/spawn/remove, `set_model`, `teleport` |
| filters | `EntityIter` (networked), `BaseEntityIter` (server-only entities) |
| memory | every `[function]` identifier for this platform in the effective gamedata resolves (`find_binary`; symbols and byte signatures), `make_function`, vtable read through `Pointer` matches the binary and the gamedata `teleport` slot (the last two need symbols: Linux only, not CS:GO) |
| cvars / keyvalues / commands | `ConVar` create/set/get, `KeyValues` round trip, `ServerCommand` |
| stringtables / precache / effects | downloadables, `Model` precache, `TempEntity('BeamPoints')` properties |
| players (bots) | properties, helpers (userid/index/playerinfo/inthandle), `teleport`, `take_damage`, messages, menus |
| counts | entity pre/post hooks (`pre_think`, `post_think`, `run_command`, `on_take_damage`), `Event` and `PreEvent`, `OnTick`, `OnClientActive`, `OnConVarChanged`, `ServerCommand`, `Delay`, `Repeat` |
| events | `event['userid']`, `event.variables.get_int()` and `.as_dict()` agree with `event.get_int()` (upstream issue #536) |

Known issues are reported as `XFAIL` (and `XPASS` once they start passing):
`runtime.site_packages_speedups` on releases with the old vendored Python (SOABI
`cpython-313-x86_64-linux-gnu`, an i686 build configured as x86_64): the markupsafe and
charset_normalizer speedups are built for the i386 tag, so they never load. With a correctly
built runtime (SOABI `...-i386-linux-gnu`) it is a normal check.

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

## Files

- `run.sh` — runner; see the header for environment variables (`SRCDS_IMAGE`, `PULL`,
  `RUNTIME=bare`, `KEEP_EXECSTACK`, `REMOVE_GAME_LIBSTDCXX`, `TIMEOUT`, `OVERLAY_REPO`)
- `Dockerfile` — test runtime on top of `srcds:<game>`
- `plugin/sp_harness/sp_harness.py` — the in-server checks
- `tools/vtdump.py` — vtable dump / gamedata check for 32-bit ELF binaries
  (`vtdump.py <server_srv.so> dump <Class>`)
- `run-windows.sh` — the Windows runner (see above)
- `tools/oci_extract.py` — extract a public image's files without Docker
- `tools/clear_execstack.py`, `tools/report.py`
