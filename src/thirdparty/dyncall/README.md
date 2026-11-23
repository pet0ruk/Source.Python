# dyncall 1.4

The source of [dyncall](https://dyncall.org) 1.4's `dyncall` (calling native functions) and
`dynload` (loading libraries) libraries, built by `src/makefiles/dyncall/dyncall.cmake`. It is
vendored as source because the upstream repository and site aren't reliably available.

- Source: https://dyncall.org/r1.4/dyncall-1.4.tar.gz
  (sha256 `14437dbbef3b6dc92483f6507eaf825ab97964a89eecae8cb347a6bec9c32aae`)
- `dyncall/`, `dynload/`, and `autovar/` and `portasm/` (headers they include) are copied from
  that tarball unchanged, apart from line endings (LF). The rest (`dyncallback/`, tests, docs,
  build systems) is left out; Source.Python doesn't use it.
- Licence: ISC, see `LICENSE`.

Source.Python changes three settings in `dyncall/dyncall_config.h` and
`dyncall/dyncall_signature.h`, and the `dlopen` flags in `dynload/dynload_unix.c` (kept as in 0.7),
each marked with a `Source.Python:` comment. They are made in separate commits on top of the stock
release, so `git log -p -- src/thirdparty/dyncall` shows them.
