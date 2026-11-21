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
   (`Dockerfile`): adds the system libraries Source.Python's bundled Python links against
   (libffi 7 and OpenSSL 1.1 from Ubuntu 20.04, libbz2/liblzma/libuuid/libpq from Debian) and
   removes L4D2's bundled `libstdc++`/`libgcc_s`, which are too old for Source.Python.
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
| memory | every `[function]` Linux symbol in the effective gamedata resolves (`find_binary`), `make_function`, vtable read through `Pointer` matches the binary and the gamedata `teleport` slot |
| cvars / keyvalues / commands | `ConVar` create/set/get, `KeyValues` round trip, `ServerCommand` |
| stringtables / precache / effects | downloadables, `Model` precache, `TempEntity('BeamPoints')` properties |
| players (bots) | properties, helpers (userid/index/playerinfo/inthandle), `teleport`, `take_damage`, messages, menus |
| counts | entity pre/post hooks (`pre_think`, `post_think`, `run_command`, `on_take_damage`), `Event` and `PreEvent`, `OnTick`, `OnClientActive`, `OnConVarChanged`, `ServerCommand`, `Delay`, `Repeat` |
| events | `event['userid']`, `event.variables.get_int()` and `.as_dict()` agree with `event.get_int()` (upstream issue #536) |

Known issues are reported as `XFAIL` (and `XPASS` once they start passing):
`runtime.site_packages_speedups` — the markupsafe/charset_normalizer speedups are built for
the i386 ABI tag while the bundled Python uses the x86_64 one, so they never load.

## Per-game notes

Bot setup lives in `GAMES` at the top of the plugin. TF2, CS:S and HL2DM remove bots on a
server without humans unless `*_bot_join_after_player 0` is set; DoD:S's `bot` needs
`sv_cheats 1`; HL2DM's bots are `hl2mp_bot_add` (NextBot, since the 2025 update).

## Files

- `run.sh` — runner; see the header for environment variables (`SRCDS_IMAGE`, `PULL`,
  `RUNTIME=bare`, `KEEP_EXECSTACK`, `TIMEOUT`, `OVERLAY_REPO`)
- `Dockerfile` — test runtime on top of `srcds:<game>`
- `plugin/sp_harness/sp_harness.py` — the in-server checks
- `tools/vtdump.py` — vtable dump / gamedata check for 32-bit ELF binaries
  (`vtdump.py <server_srv.so> dump <Class>`)
- `tools/clear_execstack.py`, `tools/report.py`
