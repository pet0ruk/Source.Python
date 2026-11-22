# dyncall 0.7

The source of [dyncall](https://dyncall.org) 0.7's `dyncall` (calling native functions) and
`dynload` (loading libraries) libraries, built by `src/makefiles/dyncall/dyncall.cmake`. It is
vendored as source because the upstream repository and site aren't reliably available.

- Source: https://dyncall.org/r0.7/dyncall-0.7.tar.gz
  (sha256 `d2aedea55478ec4b1519b379027719b47eddd3f4a2f7bc514f7cb0333bced5d0`)
- `dyncall/`, `dynload/`, and `autovar/` and `portasm/` (headers they include) are copied from
  that tarball unchanged, apart from line endings (LF). The rest (`dyncallback/`, tests, docs,
  build systems) is left out; Source.Python doesn't use it.
- Licence: ISC, see `LICENSE`.

Source.Python changes three settings in `dyncall/dyncall_config.h` and
`dyncall/dyncall_signature.h`, each marked with a `Source.Python:` comment. They are made in a
separate commit on top of the stock release, so `git log -p -- src/thirdparty/dyncall` shows them.
