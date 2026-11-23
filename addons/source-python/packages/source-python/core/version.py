# ../core/version.py

"""Provides the Source.Python version."""

# =============================================================================
# >> IMPORTS
# =============================================================================
# Python Imports
#   FuncTools
from functools import total_ordering
#   Re
import re
#   Struct
import struct
#   Sys
import sys

# Source.Python Imports
#   Cvars
from cvars.public import PublicConVar


# =============================================================================
# >> ALL DECLARATION
# =============================================================================
__all__ = ('ARCHITECTURE',
           'GIT_COMMIT',
           'PYTHON_SERIES',
           'VERSION',
           'Version',
           'get_last_successful_build_number',
           'is_unversioned',
           )


# =============================================================================
# >> CONSTANTS
# =============================================================================
#: Version of the Source.Python installation (semantic versioning, e.g.
#: ``'1.2.3'`` or ``'1.3.0-rc.1'``), set by the release workflow.
#: ``None`` for a build that isn't a release.
VERSION = None

#: The Github commit this Source.Python version was built with.
GIT_COMMIT = None

#: The series of the Python this installation runs (e.g. ``'3.13'``). Releases
#: are built for each supported series; updates stay on this one.
PYTHON_SERIES = '{}.{}'.format(*sys.version_info[:2])

#: ``'x86'`` or ``'x64'``. Updates stay on this architecture.
ARCHITECTURE = 'x64' if struct.calcsize('P') == 8 else 'x86'

_VERSION_PATTERN = re.compile(
    r'^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$')


# =============================================================================
# >> GLOBAL VARIABLES
# =============================================================================
_sp_version = PublicConVar('sp_version', str(VERSION), 'Source.Python version')


# =============================================================================
# >> CLASSES
# =============================================================================
@total_ordering
class Version(object):
    """A semantic version (``MAJOR.MINOR.PATCH[-PRERELEASE]``).

    A version is newer than its pre-releases (``1.0.0-rc.1 < 1.0.0``).
    Build metadata (``+...``) isn't supported.
    """

    def __init__(self, text):
        """Parse a version.

        :param str text:
            The version, optionally with a leading ``v`` (as in a release
            tag).
        :raise ValueError:
            Raised if the text isn't a version.
        """
        match = _VERSION_PATTERN.match(str(text).strip())
        if match is None:
            raise ValueError(f'Not a semantic version: {text!r}')

        self.major, self.minor, self.patch = map(int, match.group(1, 2, 3))
        self.prerelease = match.group(4)

    def _key(self):
        if self.prerelease is None:
            prerelease = (1,)
        else:
            # Numeric identifiers sort numerically and before alphanumeric
            # ones (semantic versioning, rule 11).
            prerelease = (0,) + tuple(
                (0, int(part), '') if part.isdigit() else (1, 0, part)
                for part in self.prerelease.split('.'))

        return (self.major, self.minor, self.patch, prerelease)

    def __eq__(self, other):
        if not isinstance(other, Version):
            return NotImplemented

        return self._key() == other._key()

    def __lt__(self, other):
        if not isinstance(other, Version):
            return NotImplemented

        return self._key() < other._key()

    def __hash__(self):
        return hash(self._key())

    def __str__(self):
        text = f'{self.major}.{self.minor}.{self.patch}'
        if self.prerelease is not None:
            text += f'-{self.prerelease}'

        return text

    def __repr__(self):
        return f'{type(self).__name__}({str(self)!r})'


# =============================================================================
# >> FUNCTIONS
# =============================================================================
def get_last_successful_build_number(timeout=3):
    """Return the newest released version this installation can update to,
    or the installed version if there is none.

    .. deprecated::
        Source.Python versions are semantic versions now, so this returns a
        version string (e.g. ``'1.2.3'``), not a build number. Use
        :func:`core.update.get_releases` and
        :func:`core.update.select_update` instead.

    :param float timeout:
        Number of seconds that need to pass until a timeout occurs.
    :rtype: str
    """
    # Import this here to fix cyclic imports
    from core.update import get_releases
    from core.update import select_update

    release = select_update(get_releases(timeout))
    return VERSION if release is None else str(release.version)


def is_unversioned():
    """Return ``True`` if this Source.Python installation has no version.

    This can happen in multiple cases:

    * This is an unofficial build (not a build from the release workflow).
    * The Python files have been updated directly from the repository.

    :rtype: bool
    """
    return VERSION is None
