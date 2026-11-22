#!/usr/bin/env python3
"""Unpack a VPK without the content a dedicated server doesn't load, as loose files.

  vpk_strip.py <dir>/<name>_dir.vpk <comma-separated extensions to drop>

Every file in the VPK whose extension is not dropped (e.g. textures, audio, UI images) is
written as a loose file under <dir>, checked against the CRC32 the VPK stores for it; then the
VPK (<name>_dir.vpk and its <name>_NNN.vpk chunks) is deleted. A loose file that already exists
is replaced, as the VPK took precedence over it. Used by prepare.sh for games whose dedicated
server ships the client's content (CS:GO: 25 GB, of which 23 GB textures, audio and UI images).
Python standard library only; VPK versions 1 and 2.
"""
import glob
import os
import struct
import sys
import zlib

ARCHIVE_IN_DIR = 0x7fff   # the file's data follows the directory tree in <name>_dir.vpk


def read_entries(f):
    signature, version, tree_size = struct.unpack('<III', f.read(12))
    if signature != 0x55aa1234 or version not in (1, 2):
        raise SystemExit(f'not a VPK v1/v2 directory file ({signature:#x}, v{version})')
    header = 12 + (16 if version == 2 else 0)
    f.seek(header)

    def string():
        data = bytearray()
        while (byte := f.read(1)) != b'\0':
            data += byte
        return data.decode('utf-8', 'surrogateescape')

    entries = []
    while (extension := string()):
        while (directory := string()):
            while (name := string()):
                crc, preload_size, archive, offset, length, terminator = \
                    struct.unpack('<IHHIIH', f.read(18))
                if terminator != 0xffff:
                    raise SystemExit(f'bad entry terminator for {directory}/{name}')
                preload = f.read(preload_size)
                path = f'{name}.{extension}' if directory == ' ' else \
                    f'{directory}/{name}.{extension}'
                entries.append((extension, path, crc, preload, archive, offset, length))
    return entries, header + tree_size


def main(directory_file, drop):
    drop = {extension.lower() for extension in drop.split(',') if extension}
    root = os.path.dirname(os.path.abspath(directory_file))
    base = directory_file[:-len('_dir.vpk')]
    with open(directory_file, 'rb') as f:
        entries, data_start = read_entries(f)
        kept = [entry for entry in entries if entry[0].lower() not in drop]
        kept.sort(key=lambda entry: (entry[4], entry[5]))   # read each chunk front to back
        written = replaced = size = 0
        chunk_number, chunk = None, None
        for extension, path, crc, preload, archive, offset, length in kept:
            data = b''
            if length:
                if archive == ARCHIVE_IN_DIR:
                    source, position = f, data_start + offset
                else:
                    if archive != chunk_number:
                        if chunk:
                            chunk.close()
                        chunk_number, chunk = archive, open(f'{base}_{archive:03d}.vpk', 'rb')
                    source, position = chunk, offset
                source.seek(position)
                data = source.read(length)
            content = preload + data
            if zlib.crc32(content) != crc:
                raise SystemExit(f'{path}: CRC mismatch')
            target = os.path.normpath(os.path.join(root, path))
            if os.path.commonpath([root, target]) != root:
                raise SystemExit(f'unsafe path in VPK: {path}')
            if os.path.lexists(target):
                replaced += 1
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, 'wb') as out:
                out.write(content)
            written += 1
            size += len(content)
        if chunk:
            chunk.close()
    dropped = len(entries) - len(kept)
    for path in glob.glob(glob.escape(base) + '_*.vpk'):
        os.remove(path)
    print(f'>> {os.path.basename(directory_file)}: {written} files unpacked ({size / 1e9:.2f} GB, '
          f'{replaced} replacing loose files), {dropped} dropped ({",".join(sorted(drop))}); '
          f'VPK deleted')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(*sys.argv[1:])
