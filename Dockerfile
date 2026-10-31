# syntax=docker/dockerfile:1

########################################
# Stage 1 - Build (Rust)
########################################
FROM rust:1-bookworm AS builder

WORKDIR /src

COPY . .

# Cache mounts keep the cargo registry and target dir between builds, so only
# changed crates recompile. The binary is copied out of the cached target dir
# because cache mounts are not part of the image.
RUN --mount=type=cache,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,target=/usr/local/cargo/git,sharing=locked \
    --mount=type=cache,target=/src/target,sharing=locked \
    cargo build --release --locked \
    && cp target/release/polaris /usr/local/bin/polaris

########################################
# Stage 2 - Web client
########################################
# The web UI lives in a separate repository (agersant/polaris-web) and ships as
# a prebuilt zip, same as the Linux release (.github/actions/make-linux-release).
FROM debian:bookworm-slim AS web

ARG POLARIS_WEB_URL=https://github.com/agersant/polaris-web/releases/latest/download/web.zip

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp
RUN curl -fsSL -o web.zip "$POLARIS_WEB_URL" && unzip -q web.zip

########################################
# Stage 3 - Runtime
########################################
FROM debian:bookworm-slim

ENV TZ=America/Sao_Paulo

# curl only serves the healthcheck.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 1000 --home-dir /data polaris \
    && mkdir -p /data /music \
    && chown polaris:polaris /data

COPY --from=builder /usr/local/bin/polaris /usr/local/bin/polaris
COPY --from=web /tmp/web /usr/share/polaris/web

USER polaris

# /data: polaris.toml, database, auth secret, thumbnails/peaks cache.
# /music: music collection, mount read-only and add it as a mount dir in the UI.
VOLUME ["/data"]

EXPOSE 5050

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -fsS http://localhost:5050/api/version || exit 1

# -f keeps the process in the foreground (no daemon, logs to stdout).
CMD ["polaris", "-f", \
     "--port", "5050", \
     "--web", "/usr/share/polaris/web", \
     "--config", "/data/polaris.toml", \
     "--data", "/data", \
     "--cache", "/data/cache"]
