# Linux build environment for Source.Python: Ubuntu 20.04 with GCC 9 and 32-bit multilib,
# the toolchain upstream releases are built with. ccache is used when CCACHE_DIR is set;
# ca-certificates for downloading the Python runtime.
FROM ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential gcc-multilib g++-multilib cmake make ccache ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /work
