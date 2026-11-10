# Spinfer (Serrano et al., USENIX ATC 2020), built as in its upstream Dockerfile, with two changes:
#  1. Debian 10 is end-of-life, so apt points at archive.debian.org (main + security + updates).
#  2. Spinfer and its Coccinelle submodule are pinned to exact commits.
FROM debian@sha256:bb3dc79fddbca7e8903248ab916bb775c96ec61014b3d02b4f06043b604726dc

ARG SPINFER_COMMIT=c47696a8bca7ecf1f6416ba3f4145859521eff58
ARG COCCI_COMMIT=9fe14e3f9b5d39f4cc7f5e18e19991f50a081d46

WORKDIR /usr/src/spinfer
RUN printf 'deb http://archive.debian.org/debian buster main\ndeb http://archive.debian.org/debian-security buster/updates main\ndeb http://archive.debian.org/debian buster-updates main\n' > /etc/apt/sources.list \
 && apt-get -o Acquire::Check-Valid-Until=false update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -q -y git make automake ocaml ocamlbuild ocaml-findlib \
      python3-numpy python3-sklearn python3-scipy \
 && rm -rf /var/lib/apt/lists/*
RUN git clone https://gitlab.inria.fr/spinfer/spinfer.git . && git checkout "$SPINFER_COMMIT" \
 && git submodule update --init coccinelle && (cd coccinelle && git checkout "$COCCI_COMMIT")
RUN /bin/bash build_dependencies.sh
RUN rm coccinelle/tools/spgen/source/spgen_lexer.mll coccinelle/tools/spgen/source/spgen_lexer.ml
RUN make && make install

RUN mkdir -p /data
WORKDIR /data
ENTRYPOINT ["spinfer"]
CMD ["-f", "index", "-o", "spinfer.cocci"]
