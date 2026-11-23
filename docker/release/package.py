#!/usr/bin/env python3
"""Make a release zip from a game's Linux and Windows release trees.

    package.py <linux release dir> <windows release dir> <out.zip>

The trees are docker/build/build.sh's and build-windows.sh's release/ directories. Files in
both must be the same, apart from line endings (the Windows tree's text files have CRLF: the
Windows Python runtime has them, and so may a Windows checkout); the Linux copy is used. Any
other difference fails, except for the files in ALLOWED_DIFFERENCES. The zip's entries are
sorted and dated SOURCE_DATE_EPOCH (default: now).
"""
import os
import sys
import time
import zipfile

# Differ between the two Python runtimes, and Source.Python doesn't use them.
ALLOWED_DIFFERENCES = {
    'addons/source-python/Python3/venv/scripts/common/Activate.ps1',
}


def files(root):
    result = {}
    for directory, _, names in os.walk(root):
        for name in names:
            path = os.path.join(directory, name)
            if os.path.islink(path):
                sys.exit(f'!! {path} is a symbolic link')
            result[os.path.relpath(path, root).replace(os.sep, '/')] = path
    return result


def same(a, b):
    with open(a, 'rb') as fa, open(b, 'rb') as fb:
        da, db = fa.read(), fb.read()
    return da == db or da.replace(b'\r\n', b'\n') == db.replace(b'\r\n', b'\n')


def main(linux_dir, windows_dir, out):
    linux, windows = files(linux_dir), files(windows_dir)
    for required in ('addons/source-python.so', 'addons/source-python/bin/core.so'):
        if required not in linux:
            sys.exit(f'!! {linux_dir} has no {required}')
    for required in ('addons/source-python.dll', 'addons/source-python/bin/core.dll'):
        if required not in windows:
            sys.exit(f'!! {windows_dir} has no {required}')

    common = linux.keys() & windows.keys()
    different = sorted(p for p in common
                       if p not in ALLOWED_DIFFERENCES and not same(linux[p], windows[p]))
    if different:
        sys.exit('!! the Linux and Windows trees differ in:\n' + '\n'.join(different[:50]))

    merged = dict(windows)
    merged.update(linux)
    date = time.gmtime(int(os.environ.get('SOURCE_DATE_EPOCH', time.time())))[:6]
    with zipfile.ZipFile(out + '.tmp', 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for name in sorted(merged):
            info = zipfile.ZipInfo(name, date)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            with open(merged[name], 'rb') as f:
                zf.writestr(info, f.read())
    os.replace(out + '.tmp', out)
    print(f'{out}: {len(merged)} files ({len(common)} in both trees, '
          f'{len(linux) - len(common)} Linux only, {len(windows) - len(common)} Windows only)')


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
