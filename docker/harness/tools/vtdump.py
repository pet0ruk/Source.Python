#!/usr/bin/env python3
"""Dump / verify Itanium-ABI vtable slots from an unstripped 32-bit or x86-64 ELF (e.g. srcds server_srv.so).

  vtdump.py <server_srv.so> dump <Class>             # print slot -> symbol
  vtdump.py <server_srv.so> check <data/entities dir> <engine> <game>
        # for every [[entry]] whose comment is a mangled name, compute offset_linux from the binary
        # using the effective (merged) gamedata for that game, and compare; exit 1 on mismatch.

Stdlib only. Slot numbering matches Source.Python's offset_linux (index after offset-to-top + RTTI).
"""
import re
import struct
import sys
from pathlib import Path


class Elf:
    """A 32-bit (i386, REL relocations) or 64-bit (x86-64, RELA relocations) ELF file."""

    def __init__(self, path):
        self.d = d = Path(path).read_bytes()
        assert d[:4] == b'\x7fELF' and d[4] in (1, 2), 'need an ELF file'
        self.bits64 = d[4] == 2
        self.ptr = 8 if self.bits64 else 4
        if self.bits64:
            shoff, = struct.unpack_from('<Q', d, 0x28)
            shentsize, shnum, shstrndx = struct.unpack_from('<HHH', d, 0x3A)
            shfmt = '<IIQQQQIIQQ'
        else:
            shoff, = struct.unpack_from('<I', d, 0x20)
            shentsize, shnum, shstrndx = struct.unpack_from('<HHH', d, 0x2E)
            shfmt = '<IIIIIIIIII'
        # (name, type, flags, addr, offset, size, link, info, addralign, entsize) either way
        self.sh = [struct.unpack_from(shfmt, d, shoff + i * shentsize) for i in range(shnum)]
        so = self.sh[shstrndx][4]
        self.names = [d[so + h[0]:d.index(b'\0', so + h[0])].decode() for h in self.sh]
        self.syms = {}           # name -> (value, size)
        self.funcs = {}          # addr -> name (prefer mangled C++ names)
        for i, h in enumerate(self.sh):
            if h[1] in (2, 11):  # SYMTAB, DYNSYM
                for name, val, size, info in self._symbols(i):
                    if name:
                        self.syms.setdefault(name, (val, size))
                        if info & 0xF == 2 and val and (val not in self.funcs or name.startswith('_Z')):
                            self.funcs[val] = name
        self.relocs = {}         # vaddr -> (type, symname, addend)
        for h in self.sh:
            if h[1] == 9 and not self.bits64:     # SHT_REL
                symtab = list(self._symbols(h[6]))
                for off in range(h[4], h[4] + h[5], 8):
                    r_off, r_info = struct.unpack_from('<II', d, off)
                    t, s = r_info & 0xFF, r_info >> 8
                    self.relocs[r_off] = (t, symtab[s][0] if s else None, None)
            elif h[1] == 4 and self.bits64:       # SHT_RELA
                symtab = list(self._symbols(h[6])) if h[6] else []
                for off in range(h[4], h[4] + h[5], 24):
                    r_off, r_info, r_addend = struct.unpack_from('<QQq', d, off)
                    t, s = r_info & 0xFFFFFFFF, r_info >> 32
                    name = None
                    if 0 < s < len(symtab):
                        name, value = symtab[s][:2]
                        if not name:                # section symbol: addend is relative to it
                            r_addend += value
                            name = None
                    self.relocs[r_off] = (t, name, r_addend)

    def _symbols(self, idx):
        h = self.sh[idx]
        stro = self.sh[h[6]][4]
        if self.bits64:
            for off in range(h[4], h[4] + h[5], 24):
                st_name, info, _, _, val, size = struct.unpack_from('<IBBHQQ', self.d, off)
                yield self.d[stro + st_name:self.d.index(b'\0', stro + st_name)].decode(), val, size, info
        else:
            for off in range(h[4], h[4] + h[5], 16):
                st_name, val, size, info = struct.unpack_from('<IIIB', self.d, off)
                yield self.d[stro + st_name:self.d.index(b'\0', stro + st_name)].decode(), val, size, info

    def word(self, vaddr):
        for h in self.sh:
            if h[3] <= vaddr < h[3] + h[5] and h[1] != 8:
                return struct.unpack_from('<Q' if self.bits64 else '<I', self.d, h[4] + vaddr - h[3])[0]
        raise KeyError(hex(vaddr))

    def vtable(self, cls):
        key = f'_ZTV{len(cls)}{cls}'
        if key not in self.syms:
            return None
        base, size = self.syms[key]
        slots = []
        for i in range(2, size // self.ptr):    # skip offset-to-top, RTTI
            a = base + self.ptr * i
            t, s, addend = self.relocs.get(a, (None, None, None))
            if s:
                name = s
            else:
                # RELA (x86-64): a local function's address is the relocation's addend
                w = addend if addend is not None else self.word(a)
                if w == 0 and i > 2 and a in self.relocs:  # unresolved
                    name = '?'
                elif self._is_typeinfo_or_offset(w):
                    break                       # secondary vtable starts
                else:
                    name = self.funcs.get(w, hex(w))
            if name.startswith('_ZTI'):         # RTTI of a secondary vtable -> stop
                slots.pop() if slots else None
                break
            slots.append(name)
        return slots

    def _is_typeinfo_or_offset(self, w):
        # negative offset-to-top of a secondary vtable
        return w >= (0xFFFFFFFFFFFF0000 if self.bits64 else 0xFFFF0000)


def method_key(mangled):
    """_ZN11CBasePlayer8PreThinkEv -> ('PreThink', 'v', '')  (class-independent)."""
    if not mangled.startswith('_ZN'):
        return None
    s = mangled[3:]
    const = ''
    if s.startswith('K'):
        const, s = 'K', s[1:]
    parts = []
    while s and s[0].isdigit():
        n = re.match(r'\d+', s).group()
        parts.append(s[len(n):len(n) + int(n)])
        s = s[len(n) + int(n):]
    if not parts or not s.startswith('E'):
        return None
    params = s[1:]
    # class-local substitutions (S_ = the class itself, S0_ ...) differ per class; normalise
    params = re.sub(r'S\d*_', 'S_', params)
    return parts[-1], params, const


def find_slot(slots, mangled):
    want = method_key(mangled)
    for i, s in enumerate(slots):
        if s == mangled or (want and method_key(s) == want):
            return i
    return None


def parse_ini(path):
    """Minimal parser for SP gamedata: returns {section: {entry: {'comment':..., key: val}}}."""
    out, sec, ent, comment = {}, None, None, None
    for line in path.read_text(errors='replace').splitlines():
        t = line.strip()
        if t.startswith('#'):
            comment = t.lstrip('# ').split()[0] if t.lstrip('# ') else None
        elif t.startswith('[[') and sec:
            ent = t.strip('[]')
            out[sec].setdefault(ent, {})
            if comment and comment.startswith('_Z'):
                out[sec][ent]['comment'] = comment
            comment = None
        elif t.startswith('['):
            sec, ent = t.strip('[]'), None
            out.setdefault(sec, {})
        elif '=' in t and sec and ent:
            k, v = (x.strip() for x in t.split('=', 1))
            out[sec][ent][k] = v
    return out


def check(elf, root, engine, game):
    root = Path(root)
    files = {p.name for d in (root, root / engine, root / engine / game) if d.is_dir() for p in d.glob('*.ini')}
    bad = ok = skipped = 0
    for name in sorted(files):
        merged = {}
        for d in (root, root / engine, root / engine / game):  # same order as GameConfigObj
            p = d / name
            if p.exists():
                for e, kv in parse_ini(p).get('virtual_function', {}).items():
                    merged.setdefault(e, {}).update(kv)
                    merged[e]['_src'] = str(p.relative_to(root))
        cls = name[:-4]
        slots = elf.vtable(cls)
        for e, kv in merged.items():
            if 'offset_linux' not in kv or 'comment' not in kv:
                continue
            if slots is None:
                skipped += 1
                print(f'  ?? {cls}.{e}: no vtable for {cls} in binary')
                continue
            got = find_slot(slots, kv['comment'])
            have = int(kv['offset_linux'])
            if got == have:
                ok += 1
            else:
                bad += 1
                print(f'  XX {cls}.{e}: data={have} binary={got} ({kv["comment"]}) [{kv["_src"]}]')
    print(f'{ok} match, {bad} mismatch, {skipped} unknown class')
    return bad == 0


if __name__ == '__main__':
    elf = Elf(sys.argv[1])
    if sys.argv[2] == 'dump':
        for i, s in enumerate(elf.vtable(sys.argv[3]) or []):
            print(i, s)
    else:
        sys.exit(0 if check(elf, *sys.argv[3:6]) else 1)
