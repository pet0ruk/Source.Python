# Minimal Source dedicated server images for testing: the server installed with steamcmd, all
# but one map removed. One image per game and platform; per-game values come from
# docker/srcds/games.json.
#
#   docker build -f docker/srcds/Dockerfile docker/srcds \
#     --build-arg APP_ID=232250 --build-arg GAME_DIR=tf --build-arg KEEP_MAP=ctf_2fort \
#     -t srcds:tf2
#
# Targets (--target):
#   linux    (default) a runnable Linux server: ./srcds_run on the test map
#   windows  the Windows server build (steamcmd on Linux, platform forced to windows) as a
#            files-only image: /srv/srcds on an empty base, nothing to run. It is a transport
#            for Windows runners, which can't run Linux containers: extract it with e.g.
#            `crane export <image> - | tar -x` (gives srv/srcds/...), or on Linux
#            `docker create` + `docker cp <id>:/srv/srcds/... .` (e.g. for server.dll).
#
# Download and pruning happen in one RUN (download-<platform>, prepare.sh), so neither the build
# cache nor the image ever holds the full map set; the final stages copy only the pruned install.
# BuildKit only builds the stages the chosen target needs.
ARG BASE=steamcmd/steamcmd:debian-trixie

FROM ${BASE} AS steamcmd
# python3 for vpk_strip.py (only the download stages have it, not the images)
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3-minimal \
 && rm -rf /var/lib/apt/lists/*
COPY prepare.sh vpk_strip.py /usr/local/bin/

FROM steamcmd AS download-linux
ARG APP_ID
ARG GAME_DIR
ARG KEEP_MAP
ARG REQUIRED_VERSION=
ARG WINDOWS_FIRST=
ARG VERIFY_VERSION=1
ARG VPK_STRIP=
ARG PRUNE=
RUN APP_ID="${APP_ID}" GAME_DIR="${GAME_DIR}" KEEP_MAP="${KEEP_MAP}" PLATFORM=linux \
    REQUIRED_VERSION="${REQUIRED_VERSION}" WINDOWS_FIRST="${WINDOWS_FIRST}" \
    VERIFY_VERSION="${VERIFY_VERSION}" VPK_STRIP="${VPK_STRIP}" PRUNE="${PRUNE}" \
    bash /usr/local/bin/prepare.sh

FROM steamcmd AS download-windows
ARG APP_ID
ARG GAME_DIR
ARG KEEP_MAP
ARG REQUIRED_VERSION=
ARG VERIFY_VERSION=1
ARG VPK_STRIP=
ARG PRUNE=
RUN APP_ID="${APP_ID}" GAME_DIR="${GAME_DIR}" KEEP_MAP="${KEEP_MAP}" PLATFORM=windows \
    REQUIRED_VERSION="${REQUIRED_VERSION}" VERIFY_VERSION="${VERIFY_VERSION}" \
    VPK_STRIP="${VPK_STRIP}" PRUNE="${PRUNE}" bash /usr/local/bin/prepare.sh

FROM scratch AS windows
COPY --from=download-windows /srv/srcds /srv/srcds
ARG APP_ID
ARG GAME_DIR
ARG KEEP_MAP
ARG REQUIRED_VERSION=
ARG GAME
LABEL org.opencontainers.image.title="srcds:${GAME}-windows" \
      org.opencontainers.image.description="Minimal ${GAME} Windows dedicated server files (map ${KEEP_MAP} only) for testing; not runnable" \
      steam.app_id="${APP_ID}" \
      steam.required_version="${REQUIRED_VERSION}" \
      srcds.game="${GAME}" \
      srcds.game_dir="${GAME_DIR}" \
      srcds.map="${KEEP_MAP}" \
      srcds.platform="windows"
# Never run; it only lets `docker create` (which needs a command) make a container to copy from.
CMD ["/none"]

FROM ${BASE} AS linux
ENV DEBIAN_FRONTEND=noninteractive
# The base already has libc6/libgcc-s1/libstdc++6 :i386. replay_srv.so (TF2) needs curl-gnutls.
RUN apt-get update \
 && apt-get install -y --no-install-recommends zlib1g:i386 libcurl3t64-gnutls:i386 ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY --from=download-linux /srv/srcds /srv/srcds
# srcds looks for the Steam client library here.
RUN mkdir -p /root/.steam/sdk32 \
 && ln -sf /srv/srcds/bin/steamclient.so /root/.steam/sdk32/steamclient.so

ARG APP_ID
ARG GAME_DIR
ARG KEEP_MAP
ARG REQUIRED_VERSION=
ARG GAME
ENV SRCDS_GAME=${GAME_DIR} SRCDS_MAP=${KEEP_MAP}
LABEL org.opencontainers.image.title="srcds:${GAME}" \
      org.opencontainers.image.description="Minimal ${GAME} dedicated server (map ${KEEP_MAP} only) for testing" \
      steam.app_id="${APP_ID}" \
      steam.required_version="${REQUIRED_VERSION}" \
      srcds.game="${GAME}" \
      srcds.game_dir="${GAME_DIR}" \
      srcds.map="${KEEP_MAP}" \
      srcds.platform="linux"

WORKDIR /srv/srcds
# Extra arguments are appended, e.g.: docker run --rm -it srcds:tf2 +maxplayers 8
ENTRYPOINT ["/bin/sh", "-c", "exec ./srcds_run -game \"$SRCDS_GAME\" -norestart +map \"$SRCDS_MAP\" \"$@\"", "--"]
