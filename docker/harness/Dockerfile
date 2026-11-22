# Test runtime: a srcds:<game> image from docker/srcds plus the system libraries that the Linux
# Python bundled with older Source.Python releases (up to v743, before the runtime from
# source-python-runtime) links against: its lib-dynload modules and compiled site-packages.
# Debian 13 no longer ships libffi 7 or OpenSSL 1.1, so those come from Ubuntu 20.04's i386
# packages; the rest are current Debian packages. Builds with the new runtime need none of them
# (RUNTIME=bare in run.sh tests that).
#
#   docker build -f docker/harness/Dockerfile docker/harness \
#     --build-arg BASE=ghcr.io/<owner>/srcds:tf2 -t sp-harness:tf2
ARG BASE

FROM ubuntu:20.04 AS legacy-libs
ENV DEBIAN_FRONTEND=noninteractive
RUN dpkg --add-architecture i386 && apt-get update \
 && apt-get install -y --no-install-recommends libffi7:i386 libssl1.1:i386 \
 && mkdir /out \
 && cp -L /usr/lib/i386-linux-gnu/libffi.so.7 /usr/lib/i386-linux-gnu/libssl.so.1.1 \
          /usr/lib/i386-linux-gnu/libcrypto.so.1.1 /out/

FROM ${BASE}
ENV DEBIAN_FRONTEND=noninteractive
#   _bz2 -> libbz2, _lzma -> liblzma, _uuid -> libuuid, psycopg2 -> libpq
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libbz2-1.0:i386 liblzma5:i386 libuuid1:i386 libpq5:i386 \
 && rm -rf /var/lib/apt/lists/*
#   _ctypes -> libffi.so.7, _ssl/_hashlib -> libssl.so.1.1 / libcrypto.so.1.1
COPY --from=legacy-libs /out/ /usr/lib/i386-linux-gnu/
# L4D2 ships an old libstdc++/libgcc_s in bin/, which srcds puts first on the library path.
# Current builds link libstdc++ statically and don't care; older releases (v743 and earlier) need
# newer symbol versions (e.g. GLIBCXX_3.4.20) and only load once they are removed (the usual fix
# on L4D2 servers): REMOVE_GAME_LIBSTDCXX=1 in run.sh.
ARG REMOVE_GAME_LIBSTDCXX=
RUN [ -z "$REMOVE_GAME_LIBSTDCXX" ] || rm -f /srv/srcds/bin/libstdc++.so.6 /srv/srcds/bin/libgcc_s.so.1
