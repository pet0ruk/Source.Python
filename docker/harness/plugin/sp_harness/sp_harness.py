# ../sp_harness/sp_harness.py

"""In-server functional tests for Source.Python on a headless dedicated server.

Loaded with ``sp plugin load sp_harness`` by docker/harness/run.sh. Runs a fixed sequence of
checks against the live engine (bots stand in for players), writes the results to
logs/sp_harness.json after every check, then quits the server. A crash therefore leaves a
results file whose "running" entry names the check that was executing.
"""

# =============================================================================
# >> IMPORTS
# =============================================================================
# Python Imports
import json
import sys
import sysconfig
import time
import traceback
from contextlib import contextmanager

# Source.Python Imports
#   Core
from core import GAME_NAME
from core import GameConfigObj
from core import PLATFORM
from core import SOURCE_ENGINE
from core import SOURCE_ENGINE_BRANCH
#   Engines
from engines.server import global_vars
from engines.server import queue_command_string
#   Entities
from entities.entity import Entity
from entities.hooks import EntityCondition
from entities.hooks import EntityPostHook
from entities.hooks import EntityPreHook
#   Commands
from commands import CommandReturn
from commands.client import ClientCommand
from commands.server import ServerCommand
#   Events
from events import Event
from events.custom import CustomEvent
from events.hooks import PreEvent
from events.resource import ResourceFile
from events.variable import ShortVariable
from events.variable import StringVariable
#   Filters
from filters.players import PlayerIter
#   Listeners
from listeners import OnClientActive
from listeners import OnConVarChanged
from listeners import OnEntityOutput
from listeners import OnLevelEnd
from listeners import OnLevelInit
from listeners import OnLevelShutdown
from listeners import OnTick
from listeners.tick import Delay
from listeners.tick import Repeat
#   Mathlib
from mathlib import Vector
#   Paths
from paths import GAME_PATH
from paths import SP_DATA_PATH


# =============================================================================
# >> GLOBAL VARIABLES
# =============================================================================
#: Per game (mod directory): commands run first ('setup'), commands that add bots (issued in
#: order until enough players join), and a server-only entity class on the test map.
GAMES = {
    'tf': {
        # without humans the bot quota manager removes bots again unless this is 0
        'setup': ['tf_bot_join_after_player 0'],
        'bots': ['tf_bot_add 3'],
        'server_only_class': 'info_player_teamspawn',
    },
    'cstrike': {
        'setup': ['bot_join_after_player 0'],
        'bots': ['bot_add_t', 'bot_add_ct', 'bot_add_t'],
        'server_only_class': 'info_player_terrorist',
    },
    'csgo': {
        'setup': ['bot_join_after_player 0', 'bot_quota_mode normal', 'mp_autoteambalance 0'],
        'bots': ['bot_add_t', 'bot_add_ct', 'bot_add_t'],
        'server_only_class': 'info_player_terrorist',
    },
    'dod': {
        'setup': ['sv_cheats 1'],                  # 'bot' is a cheat command
        'bots': ['bot', 'bot', 'bot'],
        'server_only_class': 'info_player_allies',
    },
    'hl2mp': {
        'setup': ['hl2mp_bot_join_after_player 0'],
        'bots': ['hl2mp_bot_add 3'],
        'server_only_class': 'info_player_deathmatch',
    },
    'bms': {
        'setup': ['sv_cheats 1'],                  # 'bot_add' is a cheat command
        'bots': ['bot_add', 'bot_add', 'bot_add'],
        'server_only_class': 'info_player_deathmatch',
    },
    'left4dead2': {
        'setup': ['sb_all_bot_game 1', 'sv_cheats 1'],
        'bots': ['sb_add', 'sb_add', 'sb_add'],
        'server_only_class': 'info_survivor_position',
    },
}
GAME = {'setup': [], 'bots': [], 'server_only_class': None, **GAMES.get(GAME_NAME, {})}
WANT_PLAYERS = 3
BOT_TIMEOUT = 45

RESULTS_FILE = GAME_PATH / 'logs' / 'sp_harness.json'
RESULTS = {'checks': {}, 'running': None, 'finished': False,
           'game': GAME_NAME, 'engine': SOURCE_ENGINE, 'branch': SOURCE_ENGINE_BRANCH}
CHECKS = RESULTS['checks']

#: Counters incremented by hooks/listeners; checked at the end of the run.
# StackData as seen in the first pre_think pre-hook and post_think post-hook call.
STACK_DATA = {}

COUNTS = dict.fromkeys((
    'entity_pre_hook.pre_think', 'entity_post_hook.post_think', 'entity_pre_hook.run_command',
    'entity_pre_hook.on_take_damage', 'event.player_spawn', 'pre_event.player_spawn',
    'listener.on_tick', 'listener.on_client_active', 'listener.on_convar_changed',
    'listener.on_level_shutdown', 'listener.on_level_init', 'server_command', 'delay',
    'repeat'), 0)
#: Exact counts expected for some of COUNTS (the others only need to be > 0).
EXACT_COUNTS = {'delay': 1, 'repeat': 3}
#: Event variables captured from the first player_spawn (see check_event_variables).
SPAWN_EVENTS = []
#: (name, old value, new value) for each OnConVarChanged of the harness's convars.
CONVAR_CHANGES = []
#: (index, arguments) of each sp_harness_client command a bot was made to run.
CLIENT_COMMANDS = []
#: (number, text) of each sp_harness_event received.
CUSTOM_EVENTS = []
#: Map names seen by OnLevelInit.
LEVEL_INITS = []
#: Level shutdowns/inits from the harness's changelevel on (the plugin is loaded before the
#: server's first map has finished loading, so that map's own are counted in COUNTS too).
MAP_CHANGE = {'started': False, 'shutdowns': 0, 'ends': 0, 'inits': []}
#: The file added to the downloadables table (checked again after the map change).
DOWNLOADABLE = 'sound/sp_harness/none.wav'


# =============================================================================
# >> HELPERS
# =============================================================================
def save():
    RESULTS_FILE.parent.makedirs_p()
    RESULTS_FILE.write_text(json.dumps(RESULTS, indent=2, default=repr))


def record(name, status, value=None, error=None):
    CHECKS[name] = {'status': status, 'value': None if value is None else repr(value)[:300]}
    if error:
        CHECKS[name]['error'] = error[-2000:]
    save()


class Skip(Exception):
    """Raised by a check that has nothing to test on this game."""


@contextmanager
def running(name):
    """Mark ``name`` as running in the results file, so that a crash inside it (the server
    stops before the file is written again) is reported against it, not the last check."""
    previous = RESULTS.get('running')
    RESULTS['running'] = name
    save()
    try:
        yield
    finally:
        RESULTS['running'] = previous
        save()


def check(name, fn):
    """Run ``fn``; pass if it returns a truthy value or None, fail on falsy or exception."""
    with running(name):
        try:
            value = fn()
            record(name, 'pass' if value is None or bool(value) else 'fail', value)
        except Skip as reason:
            record(name, 'skip', str(reason))
        except Exception:
            record(name, 'fail', error=traceback.format_exc())


def skip(name, reason):
    record(name, 'skip', reason)


def known_issue(name, fn, reason):
    """Like check(), for a known Source.Python problem: failing is reported as 'xfail' (does
    not fail the run), passing as 'xpass' (the issue seems fixed - turn it into a check)."""
    check(name, fn)
    entry = CHECKS[name]
    entry['status'] = 'xfail' if entry['status'] == 'fail' else 'xpass'
    entry['reason'] = reason
    save()


def expect(value, message):
    if not value:
        raise AssertionError(message)
    return value


# =============================================================================
# >> HOOKS AND LISTENERS (counted, asserted at the end)
# =============================================================================
@EntityPreHook(EntityCondition.is_player, 'pre_think')
def _pre_think(stack):
    COUNTS['entity_pre_hook.pre_think'] += 1
    if 'pre' not in STACK_DATA:
        STACK_DATA['pre'] = _stack_data_state(stack)


@EntityPostHook(EntityCondition.is_player, 'post_think')
def _post_think(stack, return_value):
    COUNTS['entity_post_hook.post_think'] += 1
    if 'post' not in STACK_DATA:
        state = _stack_data_state(stack)
        # A post-hook can read the arguments as they were before the call.
        stack.use_pre_registers = True
        state['switched'] = stack.use_pre_registers
        stack.use_pre_registers = False
        STACK_DATA['post'] = state


def _stack_data_state(stack):
    """What a hook sees of its StackData (see check_stack_data)."""
    address = stack.return_address
    return {'use_pre_registers': stack.use_pre_registers,
            'return_address': getattr(address, 'address', address),
            'this': stack[0].address}


@EntityPreHook(EntityCondition.is_player, 'run_command')
def _run_command(stack):
    COUNTS['entity_pre_hook.run_command'] += 1


@EntityPreHook(EntityCondition.is_player, 'on_take_damage')
def _on_take_damage(stack):
    COUNTS['entity_pre_hook.on_take_damage'] += 1


@Event('player_spawn')
def _on_player_spawn(game_event):
    COUNTS['event.player_spawn'] += 1
    if len(SPAWN_EVENTS) < 1:
        # Engine-owned KeyValues read through Source.Python's own KeyValues code
        # (upstream issue #536): capture all three access paths for the same key.
        with running('listener: player_spawn (reading the event variables)'):
            _capture_spawn_event(game_event)


def _capture_spawn_event(game_event):
    entry = {'get_int': game_event.get_int('userid')}
    for label, read in (
            ('getitem', lambda: game_event['userid']),
            ('variables.get_int', lambda: game_event.variables.get_int('userid')),
            ('variables.as_dict', lambda: game_event.variables.as_dict().get('userid'))):
        try:
            entry[label] = read()
        except Exception as error:
            entry[label] = f'{type(error).__name__}: {error}'
    SPAWN_EVENTS.append(entry)


@PreEvent('player_spawn')
def _pre_player_spawn(game_event):
    COUNTS['pre_event.player_spawn'] += 1


@OnTick
def _on_tick():
    COUNTS['listener.on_tick'] += 1


@OnClientActive
def _on_client_active(index):
    COUNTS['listener.on_client_active'] += 1


@OnConVarChanged
def _on_convar_changed(convar, old_value):
    if convar.name in ('sp_harness_var', 'sv_alltalk'):
        COUNTS['listener.on_convar_changed'] += 1
        CONVAR_CHANGES.append((convar.name, old_value, convar.get_string()))


@OnLevelShutdown
def _on_level_shutdown():
    COUNTS['listener.on_level_shutdown'] += 1
    if MAP_CHANGE['started']:
        MAP_CHANGE['shutdowns'] += 1


@OnLevelEnd
def _on_level_end():
    if MAP_CHANGE['started']:
        MAP_CHANGE['ends'] += 1


@OnLevelInit
def _on_level_init(map_name):
    COUNTS['listener.on_level_init'] += 1
    LEVEL_INITS.append(map_name)
    if MAP_CHANGE['started']:
        MAP_CHANGE['inits'].append(map_name)


@ClientCommand('sp_harness_client')
def _client_command(command, index):
    CLIENT_COMMANDS.append((index, command.arg_string))
    return CommandReturn.BLOCK


class Sp_Harness_Event(CustomEvent):
    """A custom game event (resource/source-python/events/sp_harness.res)."""

    number = ShortVariable('a number')
    text = StringVariable('a string')


def _on_custom_event(game_event):
    """Registered once the event is loaded (check_custom_event_load); the engine doesn't know
    it before."""
    with running('listener: sp_harness_event (reading the event variables)'):
        CUSTOM_EVENTS.append((game_event['number'], game_event['text']))


@ServerCommand('sp_harness_command')
def _server_command(command):
    COUNTS['server_command'] += 1


# =============================================================================
# >> PHASE 1: WITHOUT PLAYERS
# =============================================================================
def phase_static():
    check('runtime.python_version', lambda: sys.version.split()[0])
    check('runtime.platform', lambda: [expect(PLATFORM in ('linux', 'windows'), PLATFORM), PLATFORM][1])
    check('runtime.engine', lambda: (SOURCE_ENGINE, SOURCE_ENGINE_BRANCH, GAME_NAME))
    check('runtime.stdlib_native_modules', check_stdlib_native)
    check('runtime.soabi', lambda: sysconfig.get_config_var('SOABI'))
    check('runtime.site_packages_native', check_site_packages_native)
    check('runtime.site_packages_speedups', check_site_packages_speedups)

    check('engine.map_name', lambda: expect(global_vars.map_name, 'no map'))
    check('engine.max_clients', lambda: expect(global_vars.max_clients >= WANT_PLAYERS + 1,
                                               global_vars.max_clients))

    check('entities.worldspawn', lambda: expect(Entity(0).classname == 'worldspawn',
                                                Entity(0).classname))
    check('entities.create_origin_remove', check_entity_create)
    check('entities.set_model', check_entity_set_model)
    check('entities.teleport', check_entity_teleport)
    check('entities.output_listener', check_entity_output)
    check('filters.entity_iter_networked', check_entity_iter)
    if GAME['server_only_class']:
        check('filters.base_entity_iter_server_only', check_base_entity_iter)
    else:
        skip('filters.base_entity_iter_server_only', 'no server-only class known for game')

    check('memory.gamedata_functions', check_gamedata_functions)
    check('memory.make_function', check_make_function)
    check('memory.vtable_pointer', check_vtable_pointer)
    check('memory.callback_bool', check_callback_bool)
    check('memory.hook_refused', check_hook_refused)
    check('memory.custom_convention', check_custom_convention)
    check('memory.string_pointers', check_string_pointers)
    check('memory.platform_value', check_platform_value)
    check('weapons.scripts', check_weapon_scripts)
    check('update.stage2', check_update_stage2)
    check('update.version_order', check_version_order)
    check('update.select_release', check_select_release)
    check('perf.native_calls', check_native_call_speed)

    check('cvars.find_var', lambda: expect(
        __import__('cvars').cvar.find_var('sv_gravity') is not None, 'sv_gravity not found'))
    check('cvars.create_set_get', check_convar)
    check('cvars.dll_identifiers', check_dll_identifiers)
    check('keyvalues.roundtrip', check_keyvalues)
    check('commands.server_command', check_server_command)
    check('stringtables.downloadables', check_stringtables)
    check('events.custom_event_load', check_custom_event_load)
    fire_custom_event(1, 'before')
    check('engines.precache_model', check_precache)
    check('effects.temp_entity_properties', check_temp_entity)

    Delay(0.5, _count_delay)
    repeat = Repeat(_count_repeat)
    repeat.start(0.2, 3)

    for command in GAME['setup']:
        queue_command_string(command)
    Delay(1, add_bots, (0,))


def check_stdlib_native():
    import bz2, ctypes, hashlib, lzma, sqlite3, ssl, uuid, zlib  # noqa: F401,E401
    ssl.create_default_context()
    connection = sqlite3.connect(':memory:')
    try:
        connection.execute('select 1').fetchone()
    finally:
        connection.close()
    ctypes.CDLL(None) if PLATFORM == 'linux' else ctypes.WinDLL('kernel32')
    return {'openssl': ssl.OPENSSL_VERSION, 'sqlite': sqlite3.sqlite_version}


def check_site_packages_native(modules=None):
    """Compiled site-packages must load their C extensions, not a pure-Python fallback
    (psycopg2 is only shipped on Linux)."""
    if modules is None:
        modules = ('greenlet._greenlet',) + (('psycopg2._psycopg',) if PLATFORM == 'linux' else ())
    loaded, missing = {}, []
    for module in modules:
        try:
            path = getattr(__import__(module, fromlist=['_']), '__file__', '') or ''
        except Exception as error:
            missing.append(f'{module}: {error}')
            continue
        name = path.replace('\\', '/').rsplit('/', 1)[-1]
        if name.endswith(('.so', '.pyd')):
            loaded[module] = name
        else:
            missing.append(f'{module}: pure Python ({name})')
    expect(not missing, f'not loaded as C extensions: {missing}')
    return loaded


def check_site_packages_speedups():
    return check_site_packages_native(('markupsafe._speedups', 'charset_normalizer.md',
                                       'sqlalchemy.cyextension.collections'))


_entity_outputs = []


@OnEntityOutput
def _on_entity_output(output_name, activator, caller, value, delay):
    if caller is not None and caller.classname == 'info_target':
        _entity_outputs.append((output_name, caller.pointer.address, activator, delay))


def check_entity_output():
    """OnEntityOutput (a hook on CBaseEntityOutput::FireOutput, gamedata entity_output): an
    entity's FireUser1 input fires its OnUser1 output."""
    entity = Entity.create('info_target')
    entity.spawn()
    try:
        del _entity_outputs[:]
        entity.call_input('FireUser1', '')
        expect(_entity_outputs, 'no output fired')
        name, address, activator, delay = _entity_outputs[0]
        expect((name, address, delay) == ('OnUser1', entity.pointer.address, 0.0),
               _entity_outputs)
        return name
    finally:
        entity.remove()


def check_entity_create():
    entity = Entity.create('info_target')
    entity.spawn()
    try:
        entity.origin = Vector(1, 2, 3)
        expect(entity.index > 0, entity.index)
        expect(tuple(entity.origin) == (1.0, 2.0, 3.0), tuple(entity.origin))
    finally:
        entity.remove()


def check_entity_set_model():
    from engines.precache import Model
    entity = Entity.create('prop_dynamic_override')
    try:
        model = Model('models/error.mdl')
        entity.set_model(model)
        expect(entity.model_name == 'models/error.mdl', entity.model_name)
    finally:
        entity.remove()


def check_entity_teleport():
    entity = Entity.create('info_target')
    entity.spawn()
    try:
        entity.teleport(Vector(10, 20, 30), None, None)
        expect((entity.origin - Vector(10, 20, 30)).length < 0.01, tuple(entity.origin))
    finally:
        entity.remove()


def check_entity_iter():
    from filters.entities import EntityIter
    worlds = list(EntityIter('worldspawn'))
    expect(len(worlds) == 1, len(worlds))


def check_base_entity_iter():
    from filters.entities import BaseEntityIter
    count = len(list(BaseEntityIter(GAME['server_only_class'])))
    expect(count > 0, f'no {GAME["server_only_class"]}')
    return count


def _effective_entity_gamedata():
    """Merged entity gamedata for this game, as Source.Python's GameConfigObj sees it."""
    root = SP_DATA_PATH / 'entities'
    names = set()
    for directory in (root, root / SOURCE_ENGINE, root / SOURCE_ENGINE / GAME_NAME):
        if directory.is_dir():
            names.update(path.name for path in directory.files('*.ini'))
    return {name[:-4]: GameConfigObj(root / name) for name in sorted(names)}


def _platform_value(data, key, default=None):
    """A gamedata value the way Source.Python reads it: <key>_<platform>_x86_64 first on 64-bit
    servers, then <key>_<platform>, then <key>."""
    from memory.helpers import get_platform_value
    return get_platform_value(data, key, default)


def check_platform_value():
    """memory.helpers.get_platform_value: the 64-bit key wins only on a 64-bit server."""
    from memory.helpers import get_platform_value
    x86_64 = sys.maxsize > 2 ** 32
    data = {'offset': 1, f'offset_{PLATFORM}': 2, 'offset_x86_64': 3,
            f'offset_{PLATFORM}_x86_64': 4}
    expect(get_platform_value(data, 'offset') == (4 if x86_64 else 2), data)
    del data[f'offset_{PLATFORM}_x86_64']
    expect(get_platform_value(data, 'offset') == (3 if x86_64 else 2), data)
    expect(get_platform_value({'offset': 1}, 'offset') == 1, 'shared key')
    expect(get_platform_value({}, 'offset', 4) == 4, 'default')
    return 'x86_64' if x86_64 else 'x86'


def check_weapon_scripts():
    """weapons.scripts: the WeaponInfo attributes read what the game parsed from its weapon
    scripts (wrong gamedata offsets read neighbouring fields: other strings, garbage ints)."""
    if SOURCE_ENGINE != 'orangebox':
        raise Skip('WeaponInfo layout is only checked for orangebox games')
    from weapons.scripts import weapon_scripts
    # CS:S's database also has empty entries
    infos = [info for info in weapon_scripts if info.class_name]
    expect(len(infos) >= 5, f'only {len(infos)} weapon scripts')
    names = [info.class_name for info in infos]
    expect(all(name.isprintable() for name in names), names)
    expect(weapon_scripts[names[0]].class_name == names[0], 'lookup by class name')
    expect(all(info.is_script_parsed for info in infos), 'unparsed scripts')
    models = [(info.view_model, info.world_model) for info in infos if info.world_model]
    expect(models, 'no world models')
    expect(all(model.lower().endswith('.mdl') for pair in models for model in pair if model),
           models)
    expect(any(view != world for view, world in models), 'view model == world model')
    expect(all(-1 <= info.maximum_primary_clip < 1000 for info in infos),
           [info.maximum_primary_clip for info in infos])
    expect(all(0 <= info.slot_index < 16 for info in infos), [info.slot_index for info in infos])
    # CAmmoDef::Index(): -1 for no (or an unknown) ammo, otherwise 1 or more
    ammo = [(info.primary_ammo_name, info.primary_ammo_type) for info in infos]
    expect(all(kind == -1 for name, kind in ammo if not name), ammo)
    expect(all(-1 <= kind < 256 for name, kind in ammo), ammo)
    expect(any(kind >= 1 for name, kind in ammo), ammo)
    expect(all(-1 <= info.secondary_ammo_type < 256 for info in infos), 'secondary ammo')
    expect(any(info.single_sound for info in infos), 'no single_sound')
    # The CHudTexture pointers are only set by the client; FileWeaponInfo_t's constructor
    # zeroes all of them but iconSmall (small_icon)
    icons = ('active_icon', 'inactive_icon', 'primary_ammo_icon', 'secondary_ammo_icon',
             'crosshair_icon', 'autoaim_icon', 'zoomed_crosshair_icon', 'zommed_autoaim_icon')
    expect(all(getattr(getattr(info, icon), 'address', 0) == 0
               for info in infos for icon in icons), 'icons set')
    if GAME_NAME == 'cstrike':
        # CCSWeaponInfo's members (weapons/scripts/orangebox/cstrike/WeaponInfo.ini)
        ak47 = weapon_scripts['weapon_ak47']
        expect((ak47.price, ak47.damage, ak47.maximum_player_speed) == (2500, 36, 221),
               (ak47.price, ak47.damage, ak47.maximum_player_speed))
    return {'scripts': len(infos),
            'melee': sum(info.is_melee for info in infos),
            'right_handed': sum(info.is_built_right_handed for info in infos)}


def check_gamedata_functions():
    """Every [function] identifier in the effective gamedata for this platform resolves in its
    binary: symbols, and byte signatures ('2A' is a wildcard byte) such as Windows uses."""
    import binascii
    from memory import find_binary
    found, missing, binaries = {'symbols': 0, 'signatures': 0}, [], {}
    for cls, data in _effective_entity_gamedata().items():
        binary_name = _platform_value(data, 'binary', 'server')
        srv_check = str(_platform_value(data, 'srv_check', 'True')).lower() != 'false'
        for name, entry in data.get('function', {}).items():
            ident = _platform_value(entry, 'identifier')
            if not ident:
                continue
            kind = 'signatures' if ' ' in ident else 'symbols'
            key = (binary_name, srv_check)
            if key not in binaries:
                binaries[key] = find_binary(binary_name, srv_check)
            try:
                binaries[key][binascii.unhexlify(ident.replace(' ', '')) if kind == 'signatures'
                              else ident]
                found[kind] += 1
            except Exception:
                missing.append(f'{cls}.{name} ({ident[:40]})')
    if not any(found.values()) and not missing:
        raise Skip(f'no [function] identifiers for {PLATFORM} in this game\'s gamedata')
    expect(not missing, f'{len(missing)} unresolved: {missing[:10]}')
    return found


def _server_symbol(symbol):
    """Address of a symbol in the server binary, found the way the gamedata says (srv_check).
    CS:GO's Linux server binary is stripped, so symbol checks are skipped there."""
    from memory import find_binary
    data = GameConfigObj(SP_DATA_PATH / 'entities' / 'CBaseEntity.ini')
    srv_check = str(data.get('srv_check', 'True')).lower() != 'false'
    if PLATFORM == 'windows':
        raise Skip('Windows server binaries have no symbols')
    if SOURCE_ENGINE == 'csgo':
        raise Skip('the server binary is stripped (no symbols)')
    return find_binary('server', srv_check)[symbol]


def check_make_function():
    from memory import Convention, DataType
    function = _server_symbol('_ZN11CBaseEntity8TeleportEPK6VectorPK6QAngleS2_').make_function(
        Convention.THISCALL, (DataType.POINTER, DataType.POINTER, DataType.POINTER,
                              DataType.POINTER), DataType.VOID)
    expect(function.address, 'no address')


def check_vtable_pointer():
    """An entity's vtable read through Pointer is the binary's vtable, and the gamedata
    'teleport' slot in it holds CBaseEntity::Teleport (worldspawn doesn't override it)."""
    from memory import TYPE_SIZES
    pointer_size = TYPE_SIZES['POINTER']
    world = _server_symbol('_ZTV6CWorld')
    vtable = Entity(0).pointer.get_pointer()
    expect(vtable.address == world.address + 2 * pointer_size,   # skip offset-to-top, RTTI
           'worldspawn vtable is not _ZTV6CWorld')
    data = GameConfigObj(SP_DATA_PATH / 'entities' / 'CBaseEntity.ini')
    slot = int(data['virtual_function']['teleport']['offset_linux'])
    teleport = _server_symbol('_ZN11CBaseEntity8TeleportEPK6VectorPK6QAngleS2_').address
    expect(vtable.get_pointer(pointer_size * slot).address == teleport,
           f'slot {slot} is not CBaseEntity::Teleport')
    return f'teleport slot {slot}'


def check_callback_bool():
    """A native function returning BOOL, called through dyncall: the value is read from one
    byte (upstream #419; dyncall's DC_BOOL), and BOOL arguments arrive as passed. The function
    is a memory.Callback, which DynamicHooks creates, so both libraries are exercised."""
    from memory import Callback, Convention, DataType
    seen = []

    @Callback(Convention.CDECL, (DataType.INT, DataType.BOOL, DataType.INT, DataType.BOOL),
              DataType.BOOL)
    def callback(stack_data):
        seen.append(tuple(stack_data))
        return bool(stack_data[0])

    results = (callback(0, True, 2, False), callback(1, False, -27648, True))
    expect(results == (False, True), f'returned {results}')
    expect(seen == [(0, True, 2, False), (1, False, -27648, True)], f'arguments {seen}')
    return results


def check_hook_refused():
    """Hooking a function DynamicHooks can't patch safely (here one shorter than the hook's
    jump: xor eax, eax; ret) raises ValueError and leaves the function unchanged, instead of
    overwriting the code after it."""
    from memory import Convention, DataType, alloc
    code = (0x31, 0xC0, 0xC3, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC)
    pointer = alloc(len(code))
    for offset, byte in enumerate(code):
        pointer.set_uchar(byte, offset)

    function = pointer.make_function(Convention.CDECL, (), DataType.INT)
    try:
        function.add_pre_hook(lambda stack_data: None)
    except ValueError as error:
        message = str(error)
    else:
        raise AssertionError('the hook was added')

    expect(not function.is_hooked(), 'the function is flagged as hooked')
    after = tuple(pointer.get_uchar(offset) for offset in range(len(code)))
    expect(after == code, f'the function was changed: {after}')
    return message


def check_custom_convention():
    """A calling convention written in Python (cdecl, from the saved registers) hooks a
    function: memory.Callback calls the Python callback with the arguments the convention finds,
    and returns the value through the convention's return pointer. Registers that aren't saved
    are None. On x86-64 the convention is the platform's (the first arguments in registers)."""
    from memory import Callback, CallingConvention, Convention, DataType, Function, Pointer
    from memory import Register
    from memory import TYPE_SIZES
    seen = []
    x86_64 = TYPE_SIZES['POINTER'] == 8
    if x86_64:
        # System V: rdi, rsi; Microsoft x64: rcx, rdx
        names = ('rdi', 'rsi') if PLATFORM == 'linux' else ('rcx', 'rdx')
        stack, ret, unsaved = 'rsp', 'rax', 'r11'
        registers_saved = [Register.RSP, Register.RAX] + [getattr(Register, n.upper()) for n in names]
    else:
        names = ()
        stack, ret, unsaved = 'esp', 'eax', 'ecx'
        registers_saved = [Register.ESP, Register.EAX]

    class PythonCdecl(CallingConvention):
        def get_registers(self):
            return registers_saved

        def get_pop_size(self):
            return 0

        def get_argument_ptr(self, index, registers):
            seen.append((getattr(registers, stack).size, getattr(registers, ret).size,
                         getattr(registers, unsaved)))
            if x86_64:
                return getattr(registers, names[index]).address
            # The arguments follow the return address.
            return Pointer(registers.esp.address.get_uint() + 4 + 4 * index)

        def argument_ptr_changed(self, index, registers, ptr):
            pass

        def get_return_ptr(self, registers):
            return getattr(registers, ret).address

        def return_ptr_changed(self, registers, ptr):
            pass

    @Callback(PythonCdecl, (DataType.INT, DataType.INT), DataType.INT)
    def callback(stack_data):
        return stack_data[0] * 10 + stack_data[1]

    function = Function(callback.address, Convention.CDECL, (DataType.INT, DataType.INT),
                        DataType.INT)
    result = function(4, 2)
    expect(result == 42, f'returned {result}')
    size = TYPE_SIZES['POINTER']
    expect(seen and seen[0] == (size, size, None), f'registers {seen[:1]}')
    callback._unload_instance()
    return result


def check_stack_data():
    """StackData in entity hooks: a pre-hook uses the registers saved before the call, a
    post-hook those after it and can switch to the earlier ones; both see the call's return
    address, and the this pointer (argument 0)."""
    if 'pre' not in STACK_DATA or 'post' not in STACK_DATA:
        raise Skip('pre_think/post_think have not been called yet')
    pre, post = STACK_DATA['pre'], STACK_DATA['post']
    expect(pre['use_pre_registers'] is True, f'pre-hook {pre}')
    expect(post['use_pre_registers'] is False and post['switched'] is True, f'post-hook {post}')
    expect(pre['return_address'] and post['return_address'], f'return addresses {pre} {post}')
    expect(pre['this'] and post['this'], f'this pointers {pre} {post}')
    return {'pre': pre['use_pre_registers'], 'post': post['use_pre_registers']}


def check_dll_identifiers():
    """Each server binary registers its commands and convars under its own DLL identifier:
    Source.Python's under SP_CVAR_DLL_IDENTIFIER, the engine's and other plugins' (Metamod,
    its plugins, SourceMod, when installed with EXTRA_ADDONS) under theirs. Source.Python's
    Linux binaries used to export the SDK's convar registration code, so plugins loaded after
    them registered through Source.Python's copy and got its identifier (and lost their
    convars when Source.Python unloaded)."""
    from cvars import SP_CVAR_DLL_IDENTIFIER
    from cvars import cvar

    def identifier(name):
        base = cvar.find_base(name)
        return None if base is None else base.dll_identifier

    for name in ('sp', 'sp_version'):
        expect(identifier(name) == SP_CVAR_DLL_IDENTIFIER,
               f'{name}: {identifier(name)} != {SP_CVAR_DLL_IDENTIFIER}')
    expect(identifier('sv_gravity') != SP_CVAR_DLL_IDENTIFIER, 'sv_gravity has SP\'s identifier')

    others = {}
    for name in ('meta', 'metamod_version', 'stripper_version', 'stripper_cfg_path',
                 'stripper_file_lowercase', 'sm', 'sourcemod_version'):
        value = identifier(name)
        if value is not None:
            others[name] = value
    shared = sorted(name for name, value in others.items() if value == SP_CVAR_DLL_IDENTIFIER)
    expect(not shared, f'registered with SP\'s identifier: {shared}')
    return {'sp': SP_CVAR_DLL_IDENTIFIER, **others}


def check_string_pointers():
    """Strings written into memory as char* (Pointer.set_string_pointer, string_pointer
    attributes such as entities' string_t fields, and a string a hook returns) stay valid after
    the Python strings are freed: they point at a copy Source.Python keeps."""
    import gc
    from memory import Callback, Convention, DataType, Function, alloc
    from memory.manager import CustomType, TypeManager

    def churn():
        # Free the written strings and reuse their memory.
        gc.collect()
        return [str(n) * 40 for n in range(5000)]

    pointer = alloc(4)
    pointer.set_string_pointer(''.join(['sp_harness_', 'pointer_', str(1)]))

    types = TypeManager()

    class Named(CustomType, metaclass=types):
        _size = 4
        name = types.instance_attribute('string_pointer', 0)

    named = Named()
    named.name = '_'.join(['sp', 'harness', 'attribute'])

    @Callback(Convention.CDECL, (DataType.INT,), DataType.STRING)
    def callback(stack_data):
        return f'sp_harness_return_{stack_data[0]}'

    returns = Function(callback.address, Convention.CDECL, (DataType.INT,), DataType.STRING)
    returned = returns(7)
    garbage = churn()
    results = (pointer.get_string_pointer(), named.name, returned)
    callback._unload_instance()
    del garbage
    expect(results == ('sp_harness_pointer_1', 'sp_harness_attribute', 'sp_harness_return_7'),
           f'read back {results!r}')
    return results


def check_update_stage2():
    """The loader applied the update the harness staged (tools/stage_update.sh): the marker only
    the update had is in data/source-python, and update/ is gone."""
    from paths import UPDATE_PATH
    marker = SP_DATA_PATH / 'sp_harness_update.txt'
    if not marker.is_file() and not UPDATE_PATH.is_dir():
        raise Skip('no update was staged (NO_UPDATE=1)')
    expect(marker.is_file(), 'the staged update was not applied')
    expect(not UPDATE_PATH.exists(), f'{UPDATE_PATH} is still there')


def check_version_order():
    """core.version.Version orders semantic versions, pre-releases before their release."""
    from core.version import Version
    order = ['0.9.9', '1.0.0-alpha', '1.0.0-alpha.1', '1.0.0-alpha.beta', '1.0.0-beta.2',
             '1.0.0-beta.11', '1.0.0-rc.1', '1.0.0', '1.0.1', '1.2.0', '1.10.0', '2.0.0']
    versions = [Version(text) for text in order]
    expect(sorted(reversed(versions)) == versions, sorted(reversed(versions)))
    expect(Version('v1.2.3') == Version('1.2.3') and str(Version('v1.2.3')) == '1.2.3', 'v prefix')
    for bad in ('743', 'v743', '1.2', '1.2.3.4', '1.2.3+build', ''):
        try:
            Version(bad)
        except ValueError:
            continue
        raise AssertionError(f'{bad!r} accepted')


def check_select_release():
    """core.update picks the newest release of the installed major version that has a zip for
    this game, Python series and architecture, and skips drafts, pre-releases and other tags."""
    from core.update import CHECKSUMS_ASSET, Release, get_asset_name, select_newer_major
    from core.update import select_update
    from core.version import Version

    def release(tag, draft=False, prerelease=False, games=(SOURCE_ENGINE_BRANCH,), sums=True):
        names = [get_asset_name(tag[1:], game) for game in games] if tag[1:2].isdigit() else []
        names += [CHECKSUMS_ASSET] if sums else []
        return {'tag_name': tag, 'draft': draft, 'prerelease': prerelease,
                'html_url': f'https://example.invalid/{tag}',
                'assets': [{'name': name, 'browser_download_url': f'https://example.invalid/{name}'}
                           for name in names]}

    other = 'tf2' if SOURCE_ENGINE_BRANCH != 'tf2' else 'css'
    data = [release('v2.1.0'), release('v1.5.0', draft=True), release('v1.4.0-rc.1'),
            release('v1.4.0', prerelease=True), release('v1.3.0', games=(other,)),
            release('v1.2.1', sums=False), release('v1.2.0'), release('v1.1.0'), release('v743'),
            release('nightly')]
    releases = sorted(filter(None, map(Release.from_json, data)), key=lambda r: r.version,
                      reverse=True)
    expect([r.tag for r in releases] == ['v2.1.0', 'v1.3.0', 'v1.2.1', 'v1.2.0', 'v1.1.0'],
           releases)

    def pick(current, allow_major=False):
        chosen = select_update(releases, current, allow_major)
        return None if chosen is None else chosen.tag

    cases = {('1.1.0', False): 'v1.2.0', ('1.2.0', False): None, ('1.2.0', True): 'v2.1.0',
             ('1.2.0-rc.1', False): 'v1.2.0', ('2.1.0', True): None, (None, False): 'v2.1.0'}
    got = {key: pick(*key) for key in cases}
    expect(got == cases, got)
    newer = select_newer_major(releases, '1.2.0')
    expect(newer is not None and newer.version == Version('2.1.0'), newer)
    expect(select_newer_major(releases, '2.1.0') is None, 'newer major than 2.1.0')
    expect(get_asset_name(Version('1.2.3'), 'css', '3.13', 'x86') ==
           'source-python-css-1.2.3-py3.13.zip', 'asset name')
    expect(get_asset_name(Version('1.2.3'), 'tf2', '3.15', 'x64') ==
           'source-python-tf2-1.2.3-py3.15-x64.zip', 'x64 asset name')


def check_native_call_speed():
    """Time calls into core: a measurement to compare builds (e.g. compiler flags) on the same
    runners, not a pass/fail check. Best of 3 runs, in milliseconds."""
    from entities.helpers import index_from_edict
    from entities.helpers import edict_from_index
    from keyvalues import KeyValues
    vector, kv, edict = Vector(1, 2, 3), KeyValues('sp_harness'), edict_from_index(0)

    def best(fn, count):
        times = []
        for _ in range(3):
            start = time.perf_counter()
            fn(count)
            times.append(time.perf_counter() - start)
        return round(min(times) * 1000, 1)

    def vectors(count):
        for _ in range(count):
            (vector + vector).length

    def keyvalues(count):
        for i in range(count):
            kv.set_int('number', i)
            kv.get_int('number')

    def edicts(count):
        for _ in range(count):
            index_from_edict(edict)

    return {'vector_add_length_100k': best(vectors, 100000),
            'keyvalues_set_get_100k': best(keyvalues, 100000),
            'index_from_edict_100k': best(edicts, 100000)}


def check_convar():
    from cvars import ConVar
    variable = ConVar('sp_harness_var', '0', 'Source.Python harness test variable')
    variable.set_int(5)
    expect(variable.get_int() == 5, variable.get_int())
    bounded = ConVar('sp_harness_bounded', '1', 'Source.Python harness bounded variable', 0,
                     -2.5, 10.5)
    expect(bounded.has_min() and bounded.has_max(), 'no bounds')
    expect((bounded.min, bounded.max) == (-2.5, 10.5), (bounded.min, bounded.max))
    return {'min': bounded.min, 'max': bounded.max}


def check_keyvalues():
    from keyvalues import KeyValues
    kv = KeyValues('sp_harness')
    kv.set_string('text', 'value')
    kv.set_int('number', 7)
    kv.set_float('ratio', 0.5)
    # Create the child through the parent: a KeyValues created in Python deletes itself when
    # freed, so passing one to add_sub_key() would make the parent free it a second time.
    kv.find_key('child', True).set_int('x', 1)
    expect(kv.get_string('text') == 'value', 'string')
    expect(kv.get_int('number') == 7, 'int')
    expect(abs(kv.get_float('ratio') - 0.5) < 1e-6, 'float')
    expect(kv.find_key('child').get_int('x') == 1, 'sub key')
    return kv.as_dict()


def check_server_command():
    from engines.server import execute_server_command
    execute_server_command('sp_harness_command')
    expect(COUNTS['server_command'] == 1, COUNTS['server_command'])


DOWNLOADABLES = None


def check_stringtables():
    """Downloadables().add() puts the file into the engine's downloadables string table."""
    global DOWNLOADABLES
    from stringtables import string_tables
    from stringtables.downloads import Downloadables
    table = string_tables['downloadables']
    expect(table is not None, 'no downloadables table')
    expect(DOWNLOADABLE not in table, f'{DOWNLOADABLE} is already in the table')
    DOWNLOADABLES = Downloadables()
    DOWNLOADABLES.add(DOWNLOADABLE)
    expect(DOWNLOADABLE in table, f'{DOWNLOADABLE} was not added to the table')

    # update() and |= (from a list, a generator and a set) also add to the table right away.
    extra = [f'materials/sp_harness/update_{n}.vmt' for n in range(4)]
    DOWNLOADABLES.update(extra[:1], (path for path in extra[1:2]))
    DOWNLOADABLES |= {extra[2]}
    DOWNLOADABLES ^= {extra[3]}
    missing = [path for path in extra if path not in table or path not in DOWNLOADABLES]
    expect(not missing, f'not added: {missing}')
    return len(table)


def check_downloadables_after_map_change():
    """Source.Python adds its downloadables to the new level's table again."""
    from stringtables import string_tables
    table = string_tables['downloadables']
    expect(table is not None, 'no downloadables table')
    expect(DOWNLOADABLE in table, f'{DOWNLOADABLE} is not in the new level\'s table')


def check_custom_event_load():
    """Write the custom event's .res file and load it into the engine's event manager."""
    resource = ResourceFile('sp_harness', Sp_Harness_Event)
    resource.write()
    resource.load_events()
    from events.manager import event_manager
    event_manager.register_for_event('sp_harness_event', _on_custom_event)
    return str(resource.fullpath.relpath(GAME_PATH))


def fire_custom_event(number, text):
    try:
        Sp_Harness_Event(number=number, text=text).fire()
    except Exception as error:
        CUSTOM_EVENTS.append(f'firing ({number}, {text!r}): {type(error).__name__}: {error}')


def check_precache():
    from engines.precache import Model
    expect(Model('models/error.mdl').index > 0, 'not precached')


def check_temp_entity():
    from effects.base import TempEntity
    from engines.precache import Model
    from filters.recipients import RecipientFilter
    beam = TempEntity('BeamPoints')
    beam.start_point = Vector(1, 2, 3)
    beam.end_point = Vector(4, 5, 6)
    beam.model_index = beam.halo_index = Model('sprites/laser.vmt').index
    beam.life_time, beam.start_width, beam.end_width = 1.0, 2.0, 2.0
    expect(tuple(beam.start_point) == (1, 2, 3), tuple(beam.start_point))
    expect(tuple(beam.end_point) == (4, 5, 6), tuple(beam.end_point))
    beam.create(RecipientFilter())


def _count_delay():
    COUNTS['delay'] += 1


def _count_repeat():
    COUNTS['repeat'] += 1


# =============================================================================
# >> PHASE 2: BOTS
# =============================================================================
def add_bots(waited, issued=0):
    players = list(PlayerIter())
    if len(players) >= WANT_PLAYERS or waited >= BOT_TIMEOUT:
        record('players.bots_joined',
               'pass' if players else 'fail' if GAME['bots'] else 'skip',
               f'{len(players)} players after {waited}s ({GAME["bots"] or "no bot command"})')
        Delay(2, phase_players)
        return
    if issued < len(GAME['bots']) and waited % 3 == 0:
        queue_command_string(GAME['bots'][issued])
        issued += 1
    Delay(1, add_bots, (waited + 1, issued))


def phase_players():
    everyone = list(PlayerIter())
    players = [player for player in everyone if not player.dead] or everyone
    if not players:
        for name in ('players.properties', 'players.helpers', 'players.teleport',
                     'players.take_damage', 'messages.send', 'menus.send'):
            skip(name, 'no bots on this game')
        skip('commands.client_command', 'no bots on this game')
        skip('memory.stack_data', 'no bots on this game')
    else:
        player = players[0]
        HAD_PLAYERS.append(len(everyone))
        check('players.properties', lambda: check_player_properties(player))
        check('players.helpers', lambda: check_player_helpers(player))
        check('players.teleport', lambda: check_player_teleport(player))
        check('players.take_damage', lambda: check_take_damage(player))
        check('memory.stack_data', check_stack_data)
        check('messages.send', lambda: check_messages(player))
        check('menus.send', lambda: check_menus(player))
        if SOURCE_ENGINE == 'csgo':
            check('entities.smoke_grenade_detonate', lambda: start_smoke_detonate(player))
        # the engine runs it as if the bot had typed it; checked in finish()
        player.client_command('sp_harness_client 42 text', server_side=True)
        PLAYER_FOR_CLIENT_COMMAND.append(player.index)

    # triggers for listener/event counters, checked in finish()
    queue_command_string('sp_harness_var 9')
    # a game convar too (not sv_gravity: development-only on L4D2, its console rejects it)
    queue_command_string('sv_alltalk 1')
    if GAME['bots']:
        queue_command_string(GAME['bots'][0])
    Delay(5, change_map)


PLAYER_FOR_CLIENT_COMMAND = []
#: Set once bots have joined (by the end, after the map change, they may still be reconnecting).
HAD_PLAYERS = []


# =============================================================================
# >> PHASE 3: MAP CHANGE
# =============================================================================
def change_map():
    """changelevel to the same map: a full level shutdown and init with Source.Python (and
    this plugin) staying loaded."""
    # before the level changes, which may reset game convars
    check('cvars.console_changes', check_console_convar_changes)
    RESULTS['map_change_from'] = global_vars.map_name
    MAP_CHANGE['started'] = True
    save()
    queue_command_string(f'changelevel {global_vars.map_name}')
    Delay(1, after_map_change, (0,))


def after_map_change(waited):
    if not MAP_CHANGE['inits'] and waited < 60:
        Delay(1, after_map_change, (waited + 1,))
        return
    check('engine.map_change', check_map_change)
    check('stringtables.downloadables_after_map_change', check_downloadables_after_map_change)
    fire_custom_event(2, 'after')
    Delay(3, finish)


def check_map_change():
    """The changelevel ends the level once (OnLevelEnd) and initialises it once (OnLevelInit,
    same map). OnLevelShutdown passes on the engine's LevelShutdown calls, which some games make
    more than once per change (L4D2: twice); OnLevelEnd is Source.Python's once-per-map one."""
    expect(MAP_CHANGE['shutdowns'] >= 1, 'no OnLevelShutdown')
    expect(MAP_CHANGE['ends'] == 1, f"{MAP_CHANGE['ends']} OnLevelEnd calls")
    expect(MAP_CHANGE['inits'] == [RESULTS['map_change_from']], MAP_CHANGE['inits'])
    expect(global_vars.map_name == RESULTS['map_change_from'], global_vars.map_name)
    return {'map': MAP_CHANGE['inits'][0], 'shutdowns': MAP_CHANGE['shutdowns']}


def check_player_properties(player):
    """Player properties (network properties at gamedata/server-class offsets) agree with what
    the game's IPlayerInfo interface reports for the same bot, which doesn't use them."""
    info = player.playerinfo
    expect(player.is_bot(), 'not a bot')
    expect(player.name and player.name == info.name, (player.name, info.name))
    expect(player.userid > 0 and player.userid == info.userid, (player.userid, info.userid))
    expect(player.health > 0 and player.health == info.health, (player.health, info.health))
    expect(player.team == info.team, (player.team, info.team))
    expect((player.origin - info.origin).length < 1.0, (tuple(player.origin), tuple(info.origin)))
    if GAME_NAME == 'cstrike':
        # [based_attribute]s (CCSPlayer.ini): offsets from network properties. A bot has no clan
        # tag and no MVPs yet; a wrong offset reads a neighbouring field instead.
        expect((player.mvps, player.clan_tag) == (0, ''), (player.mvps, player.clan_tag))
    return {'name': player.name, 'health': player.health, 'team': player.team}


def check_player_helpers(player):
    from entities.helpers import edict_from_inthandle
    from players.helpers import index_from_userid
    from players.helpers import playerinfo_from_index
    from players.helpers import userid_from_index
    expect(index_from_userid(userid_from_index(player.index)) == player.index, 'userid')
    expect(playerinfo_from_index(player.index).is_fake_client(), 'playerinfo')
    expect(edict_from_inthandle(player.inthandle) is not None, 'inthandle')


def check_player_teleport(player):
    target = player.origin + Vector(0, 0, 32)
    player.teleport(target, None, None)
    expect((player.origin - target).length < 1.0, tuple(player.origin))


def check_take_damage(player):
    """The damage reaches the game (the bot's health drops, as IPlayerInfo reports it) and
    the on_take_damage hook sees it."""
    before = COUNTS['entity_pre_hook.on_take_damage']
    if SOURCE_ENGINE == 'csgo':
        # bots are immune for a while after spawning in warmup, and damage is ignored
        player.set_network_property_bool('m_bGunGameImmunity', False)
        player.set_network_property_float('m_fImmuneToGunGameDamageTime', 0.0)
    health = player.playerinfo.health
    # 10, not 1: armour halves damage and CS:GO bots spawn with it (1 would round to 0)
    player.take_damage(10)
    expect(COUNTS['entity_pre_hook.on_take_damage'] > before, 'on_take_damage hook not called')
    expect(player.playerinfo.health < health, f'health {health} -> {player.playerinfo.health}')
    return f'health {health} -> {player.playerinfo.health}'


def check_messages(player):
    from messages import HintText, SayText2, TextMsg
    sent = []
    for message in (SayText2('sp_harness'), HintText('sp_harness'), TextMsg('sp_harness')):
        message.send(player.index)
        sent.append(type(message).__name__)
    return sent


def check_menus(player):
    from menus import SimpleMenu, Text
    SimpleMenu([Text('sp_harness')]).send(player.index)


# =============================================================================
# >> FINISH
# =============================================================================
def finish():
    for name, count in COUNTS.items():
        needs_players = name.startswith('entity_') or 'player_spawn' in name or \
            name == 'listener.on_client_active'
        if needs_players and not HAD_PLAYERS:
            skip('counts.' + name, 'no bots on this game')
        elif name in EXACT_COUNTS:
            record('counts.' + name, 'pass' if count == EXACT_COUNTS[name] else 'fail',
                   f'{count} (expected {EXACT_COUNTS[name]})')
        else:
            record('counts.' + name, 'pass' if count > 0 else 'fail', count)
    check_event_variables()
    if PLAYER_FOR_CLIENT_COMMAND:
        check('commands.client_command', check_client_command)
    check('events.custom_event', check_custom_events)
    if SMOKE_EXPECTED:
        check('entities.smoke_grenade_detonate_event', check_smoke_detonate)
    RESULTS['finished'] = True
    save()
    queue_command_string('quit')


#: smokegrenade_detonate events: (entityid, userid); and the projectile/thrower it expects.
SMOKE_EVENTS = []
SMOKE_EXPECTED = []


def _on_smoke_detonate(game_event):
    with running('listener: smokegrenade_detonate (reading the event variables)'):
        SMOKE_EVENTS.append((game_event['entityid'], game_event['userid']))


def start_smoke_detonate(player):
    """Call a [function] gamedata entry found by byte signature (CSmokeGrenadeProjectile
    .detonate, i.e. SmokeDetonate) on a smoke grenade projectile thrown by a bot; the game then
    fires smokegrenade_detonate for it (checked in finish()), which shows the signature found
    that function and the call worked, not only that the bytes were found."""
    from events.manager import event_manager
    event_manager.register_for_event('smokegrenade_detonate', _on_smoke_detonate)
    grenade = Entity.create('smokegrenade_projectile')
    grenade.origin = player.origin + Vector(0, 0, 16)
    grenade.thrower = player.inthandle
    grenade.owner_handle = player.inthandle
    grenade.spawn()
    SMOKE_EXPECTED.append((grenade.index, player.userid))
    grenade.detonate()
    return SMOKE_EXPECTED[0]


def check_smoke_detonate():
    expect(SMOKE_EXPECTED[0] in SMOKE_EVENTS, (SMOKE_EXPECTED, SMOKE_EVENTS))
    return SMOKE_EVENTS


def check_console_convar_changes():
    """Values set from the server console (phase_players) are what Source.Python reads, and
    OnConVarChanged was given the old and new values."""
    from cvars import cvar
    for name, value in (('sp_harness_var', 9), ('sv_alltalk', 1)):
        expect(cvar.find_var(name).get_int() == value, (name, cvar.find_var(name).get_int()))
    alltalk = [change for change in CONVAR_CHANGES if change[0] == 'sv_alltalk']
    expect(alltalk and alltalk[-1][2] == '1' and alltalk[-1][1] != '1', CONVAR_CHANGES)
    harness = [change for change in CONVAR_CHANGES if change[0] == 'sp_harness_var']
    expect(harness and harness[-1][1:] == ('5', '9'), CONVAR_CHANGES)
    return CONVAR_CHANGES


def check_client_command():
    """The command a bot was made to run reached the ClientCommand, with its index and
    arguments."""
    expect(CLIENT_COMMANDS == [(PLAYER_FOR_CLIENT_COMMAND[0], '42 text')], CLIENT_COMMANDS)
    return CLIENT_COMMANDS


def check_custom_events():
    """The custom event fired before the map change and the one fired after it both arrived,
    with their values (the .res file is loaded once, as plugins do at load)."""
    expect(CUSTOM_EVENTS == [(1, 'before'), (2, 'after')], CUSTOM_EVENTS)
    return CUSTOM_EVENTS


def check_event_variables():
    """event['key'], event.variables and event.get_int must agree (upstream issue #536)."""
    if not SPAWN_EVENTS:
        skip('events.variables_match_get_int', 'no player_spawn event seen')
        return
    entry = SPAWN_EVENTS[0]
    wanted = entry['get_int']
    bad = {k: v for k, v in entry.items() if k != 'get_int' and v != wanted}
    record('events.variables_match_get_int', 'fail' if bad or not wanted else 'pass', entry)


def load():
    RESULTS['started'] = time.time()
    save()
    Delay(2, phase_static)
