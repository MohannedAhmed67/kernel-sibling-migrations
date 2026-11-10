# Pinned toolchain for the sibling-migration feasibility study.
# Ubuntu 22.04 ships GCC 11, contemporary with the kernels we study (v5.10, Dec 2020 .. v6.10, Jul 2024),
# so build failures reflect the patch under test rather than a too-new compiler.
FROM ubuntu@sha256:076e7bf82319619f28dd0aa9c02ab34b055ad37100395b4f49a2ffba04fb5e11

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git ca-certificates \
      build-essential flex bison bc libelf-dev libssl-dev cpio kmod \
      python3 python3-matplotlib \
      coccinelle \
 && rm -rf /var/lib/apt/lists/*

# The repo is bind-mounted from the host; tell git that is fine.
RUN git config --system --add safe.directory '*'

WORKDIR /work
