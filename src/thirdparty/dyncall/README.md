# dyncall 0.7

The `dyncall` (calling native functions) and `dynload` (loading libraries) parts of
[dyncall](https://dyncall.org) 0.7, built by `src/makefiles/dyncall/dyncall.cmake`. They are
vendored as source because the upstream repository and site aren't reliably available.

- Source: https://dyncall.org/r0.7/dyncall-0.7.tar.gz
  (sha256 `d2aedea55478ec4b1519b379027719b47eddd3f4a2f7bc514f7cb0333bced5d0`)
- `dyncall/`, `dynload/` and the headers they include from `autovar/` and `portasm/` are copied unchanged from that tarball (line endings normalised to LF);
  the rest (`dyncallback/`, `test/`, `doc/`, build systems) is left out, Source.Python doesn't use them.
- Licence: ISC, see `LICENSE`.

Source.Python changes three settings in the headers; see `git log -- src/thirdparty/dyncall` for
the commit that makes them on top of the stock release.
