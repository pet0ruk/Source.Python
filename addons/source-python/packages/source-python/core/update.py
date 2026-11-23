# ../core/update.py

"""Provides functions to update Source.Python from its GitHub releases."""

# =============================================================================
# >> IMPORTS
# =============================================================================
# Python Imports
import hashlib
import json
import time

from zipfile import ZipFile
from urllib.request import urlopen

# Source.Python Imports
#   Core
from core import PLATFORM
from core import SOURCE_ENGINE_BRANCH
from core.logger import core_logger
from core.version import ARCHITECTURE
from core.version import PYTHON_SERIES
from core.version import VERSION
from core.version import Version
#   Paths
from paths import ADDONS_PATH
from paths import GAME_PATH
from paths import UPDATE_PATH
#   KeyValues
from keyvalues import KeyValues


# =============================================================================
# >> ALL DECLARATION
# =============================================================================
__all__ = (
    'CHECKSUMS_ASSET',
    'RELEASES_URL',
    'Release',
    'do_full_update',
    'download_file',
    'get_asset_name',
    'get_releases',
    'select_newer_major',
    'select_update',
    'update_in_progress',
)


# =============================================================================
# >> GLOBAL VARIABLES
# =============================================================================
# Don't use __getattr__ here. 'update' is a method of the _LogInstance class.
update_logger = core_logger['update']

BINARY_EXT = 'so' if PLATFORM == 'linux' else 'dll'

SP_VDF1 = 'addons/source-python'
SP_VDF2 = 'addons/source-python2'

UPDATE_ZIP_FILE = UPDATE_PATH / 'source-python.zip'
VDF_FILE = ADDONS_PATH / 'source-python.vdf'
LOADER_FILE = ADDONS_PATH / f'source-python.{BINARY_EXT}'
LOADER_UPDATE_FILE = UPDATE_PATH / 'addons' / f'source-python.{BINARY_EXT}'
VDF_UPDATE_FILE = UPDATE_PATH / 'addons' / 'source-python.vdf'

#: The GitHub releases of Source.Python (newest first).
RELEASES_URL = (
    'https://api.github.com/repos/pet0ruk/Source.Python/releases?per_page=100')

#: The release asset with the sha256 of each of the release's zips.
CHECKSUMS_ASSET = 'SHA256SUMS'

#: Seconds a fetched list of releases is reused (GitHub allows 60 requests
#: an hour from an IP address without authentication).
RELEASES_CACHE_TIME = 3600

DEFAULT_TIMEOUT = 3
DOWNLOAD_TIMEOUT = 30

#: Indicates, whether an update is in progress (stage 1 has been applied).
update_in_progress = False

_releases_cache = None


# =============================================================================
# >> CLASSES
# =============================================================================
class Release(object):
    """A published Source.Python release."""

    def __init__(self, version, tag, url, assets):
        """Store the release's data.

        :param Version version:
            The release's version.
        :param str tag:
            The release's tag (e.g. ``'v1.2.3'``).
        :param str url:
            The release's page.
        :param dict assets:
            Download URL of each asset, by file name.
        """
        self.version = version
        self.tag = tag
        self.url = url
        self.assets = assets

    def __repr__(self):
        return f'{type(self).__name__}({self.tag!r})'

    @classmethod
    def from_json(cls, data):
        """Return a release from GitHub's JSON for it, or ``None`` for a
        draft, a pre-release or a tag that isn't a version.

        :param dict data:
            A release, as returned by GitHub's releases API.
        :rtype: Release
        """
        if data.get('draft') or data.get('prerelease'):
            return None

        try:
            version = Version(data['tag_name'])
        except ValueError:
            return None

        if version.prerelease is not None:
            return None

        assets = {
            asset['name']: asset['browser_download_url']
            for asset in data.get('assets', ())}
        return cls(version, data['tag_name'], data.get('html_url'), assets)


# =============================================================================
# >> FUNCTIONS
# =============================================================================
def download_file(url_path, file_path, timeout=DOWNLOAD_TIMEOUT):
    """Download a file from an URL to a specific file.

    :param str url_path:
        The URL that should be opened.
    :param str file_path:
        The file where the content of the URL should be stored.
    :param float timeout:
        Number of seconds that need to pass until a timeout occurs.
    """
    update_logger.log_debug(f'Downloading file ({url_path}) to {file_path} ...')
    now = time.time()

    with urlopen(url_path, timeout=timeout) as url:
        data = url.read()

    with file_path.open('wb') as f:
        f.write(data)

    update_logger.log_info(
        'File has been downloaded. Time elapsed: {:0.2f} seconds'.format(
            time.time()-now))


def get_asset_name(version, game=SOURCE_ENGINE_BRANCH,
        python_series=PYTHON_SERIES, architecture=ARCHITECTURE):
    """Return the name of a release's zip for a game.

    :param Version version:
        The release's version.
    :param str game:
        The build branch (e.g. ``'css'``).
    :param str python_series:
        The Python series (e.g. ``'3.13'``).
    :param str architecture:
        ``'x86'`` or ``'x64'``.
    :rtype: str
    """
    suffix = '-x64' if architecture == 'x64' else ''
    return f'source-python-{game}-{version}-py{python_series}{suffix}.zip'


def get_releases(timeout=DEFAULT_TIMEOUT, use_cache=True):
    """Return Source.Python's published releases, newest first.

    Drafts, pre-releases and tags that aren't versions are left out.

    :param float timeout:
        Number of seconds that need to pass until a timeout occurs.
    :param bool use_cache:
        Whether a list fetched in the last :data:`RELEASES_CACHE_TIME` seconds
        may be returned.
    :rtype: list
    """
    global _releases_cache
    if (use_cache and _releases_cache is not None and
            time.time() - _releases_cache[0] < RELEASES_CACHE_TIME):
        return list(_releases_cache[1])

    update_logger.log_debug('Getting releases...')
    with urlopen(RELEASES_URL, timeout=timeout) as url:
        data = json.load(url)

    releases = sorted(
        filter(None, map(Release.from_json, data)),
        key=lambda release: release.version, reverse=True)
    _releases_cache = (time.time(), releases)
    return list(releases)


def _installable(releases, game):
    for release in releases:
        if (get_asset_name(release.version, game) in release.assets and
                CHECKSUMS_ASSET in release.assets):
            yield release


def select_update(releases, current=VERSION, allow_major=False,
        game=SOURCE_ENGINE_BRANCH):
    """Return the newest release to update to, or ``None``.

    Only releases with a zip for this game, Python series and architecture
    are considered. Unless ``allow_major`` is set, the release must have the
    installed major version: a new major version can break plugins. An
    installation without a version gets the newest release.

    :param list releases:
        The releases (see :func:`get_releases`).
    :param str current:
        The installed version, or ``None``.
    :param bool allow_major:
        Whether a newer major version may be returned.
    :param str game:
        The build branch.
    :rtype: Release
    """
    current = None if current is None else Version(current)
    for release in _installable(releases, game):
        if current is None:
            return release

        if release.version <= current:
            continue

        if allow_major or release.version.major == current.major:
            return release

    return None


def select_newer_major(releases, current=VERSION, game=SOURCE_ENGINE_BRANCH):
    """Return the newest release of a newer major version, or ``None``.

    :param list releases:
        The releases (see :func:`get_releases`).
    :param str current:
        The installed version, or ``None`` (then ``None`` is returned).
    :param str game:
        The build branch.
    :rtype: Release
    """
    if current is None:
        return None

    current = Version(current)
    for release in _installable(releases, game):
        if release.version.major > current.major:
            return release

    return None


# =============================================================================
# >> FULL SP UPDATE
# =============================================================================
def do_full_update(release, timeout=DOWNLOAD_TIMEOUT):
    """Starts a full update of Source.Python to a release.

    A restart of the server and possibly manual work is required. Please see
    the Source.Python log for the instructions.

    :param Release release:
        The release to install (see :func:`select_update`).
    :param float timeout:
        Number of seconds that need to pass until a timeout occurs.
    :raise ValueError:
        Raised if the release has no zip for this installation or the
        download doesn't match its checksum.
    """
    global update_in_progress
    if update_in_progress:
        update_logger.log_message(
            'An update is already in progress. Please follow the instructions '
            'in the log.')
        return

    # Make sure there is a clean update directory
    _clean_update_dir()
    try:
        _download_release(release, timeout)
        _apply_update_stage1()
        update_in_progress = True
    except:
        # Make sure to leave a clean update directory, so the loader doesn't
        # get confused.
        _clean_update_dir()
        raise


def _clean_update_dir():
    """Clear or create the update directory."""
    if UPDATE_PATH.exists():
        for f in UPDATE_PATH.iterdir():
            if f.is_file():
                f.remove()
            else:
                f.rmtree()
    else:
        UPDATE_PATH.mkdir()


def _download_release(release, timeout=DOWNLOAD_TIMEOUT):
    """Download a release's zip for this installation and verify it against
    the release's checksums.
    """
    name = get_asset_name(release.version)
    if name not in release.assets or CHECKSUMS_ASSET not in release.assets:
        raise ValueError(f'{release.tag} has no {name} (or no checksums).')

    update_logger.log_message(f'Downloading Source.Python {release.version}...')
    with urlopen(release.assets[CHECKSUMS_ASSET], timeout=timeout) as url:
        checksums = url.read().decode()

    expected = None
    for line in checksums.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1].lstrip('*') == name:
            expected = parts[0].lower()

    if expected is None:
        raise ValueError(f'{CHECKSUMS_ASSET} of {release.tag} has no {name}.')

    download_file(release.assets[name], UPDATE_ZIP_FILE, timeout)
    actual = hashlib.sha256(UPDATE_ZIP_FILE.read_bytes()).hexdigest()
    if actual != expected:
        raise ValueError(
            f'{name} does not match its checksum (sha256 {actual}, expected '
            f'{expected}).')


def _apply_update_stage1():
    """Apply stage 1 of the version update."""
    update_logger.log_message('Applying Source.Python update stage 1...')

    # Extract all files to the update directory
    with ZipFile(UPDATE_ZIP_FILE) as zip:
        zip.extractall(UPDATE_PATH)

    UPDATE_ZIP_FILE.remove()
    VDF_UPDATE_FILE.remove()

    if PLATFORM == 'windows':
        _apply_update_stage1_windows()
    else:
        _apply_update_stage1_linux()


def _apply_update_stage1_windows():
    """Apply the Windows specific part of stage 1.

    On Windows files that are currently in use (``source-python.dll``) can't be
    replaced. Thus, this function checks if ``source-python.vdf`` exists. If it
    does, the new ``source-python.dll`` is copied to the addons directory with
    a new name (``source-python2.dll``). After that the VDF entry is modified
    to point to the new loader.

    If ``source-python.vdf`` does not exist, manual action is required.
    """
    if not VDF_FILE.is_file():
        update_logger.log_message(
            f'Stage 1 has been applied. Please shutdown your server and move '
            f'(do not copy) {LOADER_UPDATE_FILE} to {LOADER_FILE}. After that '
            f'start your server to apply stage 2.')
    else:
        update_logger.log_debug('Determining current VDF entry...')
        kv = KeyValues.from_file(VDF_FILE)

        # Get the current and new entry for the VDF file
        current_entry = kv.get_string('file')
        if current_entry == SP_VDF2:
            new_entry = SP_VDF1
        elif current_entry == SP_VDF1:
            new_entry = SP_VDF2
        else:
            raise ValueError(f'Unexpected entry in VDF: {current_entry}')

        update_logger.log_debug(f'Current VDF entry: {current_entry}')
        update_logger.log_debug(f'New VDF entry: {new_entry}')

        update_logger.log_debug('Moving new loader binary to game directory...')
        LOADER_UPDATE_FILE.move(GAME_PATH / f'{new_entry}.{BINARY_EXT}')

        kv.set_string('file', new_entry)
        kv.save_to_file(VDF_FILE)

        update_logger.log_message(
            'Stage 1 has been applied. Restart your server to apply stage 2.')


def _apply_update_stage1_linux():
    """Apply the Linux specific part of stage 1."""
    update_logger.log_debug('Moving new loader binary to game directory...')
    LOADER_UPDATE_FILE.move(LOADER_FILE)
    update_logger.log_message(
        'Stage 1 has been applied. Restart your server to apply stage 2.')
