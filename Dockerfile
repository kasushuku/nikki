# syntax=docker/dockerfile:1

# =============================================================================
# にっき.かすしゅく.みんな — Dream SSRサーバー
#
#   docker build -t nikki .
#   docker run --rm -p 8080:8080 nikki
#
# Vercel Functionsのコンテナはlinux/amd64で動く。arm64のマシンからpushする
# 場合は `docker build --platform=linux/amd64` を付けること。
# Vercel側の既定listen portは80なので、Project Settingsで PORT=8080 を設定
# するか、この ENV PORT を80に変える。
# =============================================================================

ARG DEBIAN_VERSION=12
ARG OCAML_VERSION=5.3

# --- build -------------------------------------------------------------------
FROM ocaml/opam:debian-${DEBIAN_VERSION}-ocaml-${OCAML_VERSION} AS build

# Dreamが引く lwt(libev) / tls(gmp) / ssl / zlib のCヘッダ
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libev-dev libssl-dev libgmp-dev zlib1g-dev pkg-config m4 \
 && rm -rf /var/lib/apt/lists/*
USER opam

WORKDIR /home/opam/nikki

# 依存解決を先に済ませ、ソース変更でopam層が無効化されないようにする
COPY --chown=opam:opam dune-project app.opam ./
RUN opam update \
 && opam install --deps-only --yes . \
 && opam clean --all --yes

# Melangeを入れたら web/ もbuild stageへcopyし、静的アセットは
# _build/default/web/assets からruntimeへ渡すこと
COPY --chown=opam:opam dune ./
COPY --chown=opam:opam app ./app
RUN opam exec -- dune build --profile release app/bin/main.exe

# --- runtime -----------------------------------------------------------------
FROM debian:${DEBIAN_VERSION}-slim AS runtime

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates libev4 libssl3 libgmp10 zlib1g \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --create-home --uid 10001 nikki

WORKDIR /srv/nikki

COPY --from=build /home/opam/nikki/_build/default/app/bin/main.exe /usr/local/bin/nikki
# Dream.static は CWD 相対で解決するため web/ の位置を WORKDIR に合わせる
COPY web ./web
# content/ は nikki-content のsubmodule。checkout後に有効化する
# COPY content ./content

USER nikki
ENV PORT=8080
EXPOSE 8080

CMD ["/usr/local/bin/nikki"]
