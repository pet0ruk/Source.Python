#!/usr/bin/env python3
"""Clear the executable-stack flag of a 32-bit ELF shared object (like `execstack -c`).

  clear_execstack.py <file.so>...

Linux builds of core.so link prebuilt dyncall objects that lack a .note.GNU-stack section, so
the linker marks the whole object as needing an executable stack. glibc >= 2.41 refuses to
dlopen such objects ("cannot enable executable stack as shared object requires"). This clears
PF_X on the PT_GNU_STACK program header. Prints what it did; exit 1 if a file is not ELF32.
"""
import struct
import sys

PT_GNU_STACK = 0x6474E551
PF_X = 0x1


def clear(path):
    with open(path, 'r+b') as f:
        d = bytearray(f.read())
        if d[:4] != b'\x7fELF' or d[4] != 1:
            print(f'{path}: not a 32-bit ELF', file=sys.stderr)
            return False
        phoff, = struct.unpack_from('<I', d, 0x1C)
        phentsize, phnum = struct.unpack_from('<HH', d, 0x2A)
        for i in range(phnum):
            off = phoff + i * phentsize
            p_type, = struct.unpack_from('<I', d, off)
            if p_type != PT_GNU_STACK:
                continue
            flags, = struct.unpack_from('<I', d, off + 24)
            if not flags & PF_X:
                print(f'{path}: stack already non-executable')
                return True
            struct.pack_into('<I', d, off + 24, flags & ~PF_X)
            f.seek(0)
            f.write(d)
            print(f'{path}: cleared executable stack flag')
            return True
        print(f'{path}: no PT_GNU_STACK header (nothing to do)')
        return True


if __name__ == '__main__':
    ok = [clear(p) for p in sys.argv[1:]]
    sys.exit(0 if ok and all(ok) else 1)
