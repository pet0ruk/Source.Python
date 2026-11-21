# Minimal Source dedicated server image for testing: the server installed with steamcmd, all
# but one map removed. One image per game; per-game values come from docker/srcds/games.json.
#
#   docker build -f docker/srcds/Dockerfile docker/srcds \
#     --build-arg APP_ID=232250 --build-arg GAME_DIR=tf --build-arg KEEP_MAP=ctf_2fort \
#     -t srcds:tf2
#
# Download and pruning happen in one RUN, so neither the build cache nor the image ever holds
# the full map set; the final stage copies only the pruned install.
ARG BASE=steamcmd/steamcmd:debian-trixie

FROM ${BASE} AS download
ARG APP_ID
ARG GAME_DIR
ARG KEEP_MAP
ARG REQUIRED_VERSION=
ARG WINDOWS_FIRST=
ARG VERIFY_VERSION=1
COPY prepare.sh /usr/local/bin/prepare.sh
RUN APP_ID="${APP_ID}" GAME_DIR="${GAME_DIR}" KEEP_MAP="${KEEP_MAP}" \
    REQUIRED_VERSION="${REQUIRED_VERSION}" WINDOWS_FIRST="${WINDOWS_FIRST}" \
    VERIFY_VERSION="${VERIFY_VERSION}" bash /usr/local/bin/prepare.sh

FROM ${BASE}
ENV DEBIAN_FRONTEND=noninteractive
# The base already has libc6/libgcc-s1/libstdc++6 :i386. replay_srv.so (TF2) needs curl-gnutls.
RUN apt-get update \
 && apt-get install -y --no-install-recommends zlib1g:i386 libcurl3t64-gnutls:i386 ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY --from=download /srv/srcds /srv/srcds
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
      srcds.map="${KEEP_MAP}"

WORKDIR /srv/srcds
# Extra arguments are appended, e.g.: docker run --rm -it srcds:tf2 +maxplayers 8
ENTRYPOINT ["/bin/sh", "-c", "exec ./srcds_run -game \"$SRCDS_GAME\" -norestart +map \"$SRCDS_MAP\" \"$@\"", "--"]
