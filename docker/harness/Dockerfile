# Test image: a srcds:<game> image from docker/srcds, as shipped, plus gdb (run.sh starts the
# server under it, tools/srcds-gdb.sh, so a crash leaves a backtrace), and without a game's
# bundled libstdc++/libgcc_s when games.json asks for it (remove_game_libstdcxx; run.sh passes it
# on): CS:GO ships a libgcc_s older than the image's libstdc++, and its engine then can't load.
# Source.Python itself needs nothing from the image (libstdc++ is linked statically, and the
# Python runtime brings its own libraries).
#
#   docker build -f docker/harness/Dockerfile docker/harness \
#     --build-arg BASE=ghcr.io/<owner>/srcds:csgo --build-arg REMOVE_GAME_LIBSTDCXX=1 \
#     -t sp-harness:csgo
ARG BASE
FROM ${BASE}
RUN apt-get update \
 && apt-get install -y --no-install-recommends gdb \
 && rm -rf /var/lib/apt/lists/*
COPY tools/srcds-gdb.sh /usr/local/bin/srcds-gdb
ARG REMOVE_GAME_LIBSTDCXX=
RUN [ -z "$REMOVE_GAME_LIBSTDCXX" ] || rm -f /srv/srcds/bin/libstdc++.so.6 /srv/srcds/bin/libgcc_s.so.1
