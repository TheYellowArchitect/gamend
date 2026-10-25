# syntax=docker/dockerfile:1
# Two images from one build.
#
#   docker build .                      → the full image (default)
#   docker build --target release .     → an OTP release, ~11x smaller
#
# Both share the `builder` stage, so the expensive half — ~140 dependencies
# and their NIFs — is compiled once and cached once no matter which target you
# ask for. `full` is declared last so a bare `docker build .` keeps producing
# the image it always has.
#
# The system packages, the Rust toolchain and the start commands are not here:
# they are the base images in docker/ (docker/README.md), which every app built
# on Gamend starts FROM too, published by .github/workflows/base-images.yml.
#
#   full     ships everything used to build it and runs `mix phx.server`. Large
#            (~6 GB), and the only variant whose admin UI can build plugin
#            bundles: Gamend.Hooks.PluginBuilder shells out to `mix`.
#   release  carries the app, ERTS and a handful of shared libraries. No
#            compilers, no Rust, no source. The "Build bundle" control disables
#            itself and says why.
#
# The adapter is a compile-time choice (see config/host_config.exs), so an
# image is specific to one:
#
#   docker build --target release --build-arg GAMEND_DB_ADAPTER=postgres .

ARG BUILDER_IMAGE=ghcr.io/appsinacup/gamend-builder:elixir-1.20
# Tracks the builder's Debian release: the release carries ERTS and NIFs linked
# against that libc. gamend-builder is Debian 13 (trixie).
ARG RUNNER_IMAGE=ghcr.io/appsinacup/gamend-runtime:trixie

# Declared globally so every stage can redeclare them. A stage does not inherit
# another stage's ENV, and these drive runtime behaviour — adapter selection,
# where plugins load from, the reported version — so the release target has to
# carry them across deliberately. The full target gets them for free by being
# the builder.
ARG GAMEND_DB_ADAPTER=sqlite
ARG GAMEND_CONTENT_PLUGINS_DIR=modules/plugins_examples
ARG GAMEND_CONTENT_APP_VERSION=1.0.0

# ── Builder ───────────────────────────────────────────────────────────────
# gamend-builder: Elixir, the system packages (ImageMagick for the srcset
# variants host.responsive_images cuts, brotli for bin/compress-static, …),
# Rust for ex_sctp, Hex and Rebar, WORKDIR /app (docker/builder/Dockerfile).
FROM ${BUILDER_IMAGE} AS builder

# Set environment to production
ENV MIX_ENV=prod

# Database adapter for compile-time selection (sqlite or postgres).
# Set to "postgres" when deploying with PostgreSQL.
ARG GAMEND_DB_ADAPTER
ENV GAMEND_DB_ADAPTER=${GAMEND_DB_ADAPTER}

# Plugin build configuration
ARG GAMEND_CONTENT_PLUGINS_DIR
ENV GAMEND_CONTENT_PLUGINS_DIR=${GAMEND_CONTENT_PLUGINS_DIR}

COPY mix.exs mix.lock ./

# Umbrella apps: include their mix.exs files so deps can be resolved in a cached layer
COPY apps/gamend_web/mix.exs apps/gamend_web/mix.exs
COPY apps/gamend_core/mix.exs apps/gamend_core/mix.exs
# The GDScript transpiler (gamend_plugin_tools), a path dependency of the host.
# Without its mix.exs here, deps.get would resolve it from GitHub instead.
COPY sdk_tools/mix.exs sdk_tools/mix.exs

# Install dependencies
RUN mix deps.get

# Compile-time config must be present before deps compile (mdex reads its
# syntax highlighter from config). Copied on its own so the layer only busts
# when config changes, not on every source commit.
COPY config config

# Compile external deps (hex + git, including the Rust NIFs) in a cached
# layer. Without this, `COPY . .` below invalidated `mix compile` on every
# commit and all ~140 deps rebuilt from scratch each CI run. Local path deps
# (apps/*) are skipped: their sources arrive with COPY and compile next.
RUN mix deps.compile --skip-local-deps

COPY . .

# Build any plugins that ship with the repository (gamend-builder's helper; an
# app's Dockerfile runs the same line).
RUN gamend-build-plugins --verbose

# Compile the application FIRST (generates phoenix-colocated hooks)
RUN mix compile

# Build and digest static assets for production for the root host app.
RUN mix assets.deploy

# A release copies each application's priv from _build, and prod.exs points
# cache_static_manifest at {:gamend_host, "priv/static/cache_manifest.json"} —
# resolved through the code server, not the project tree. Mix usually symlinks
# priv into _build, in which case this is a no-op; where it copied instead, the
# digested assets would be missing from the release without this.
RUN gamend-copy-static gamend_host --require

# Version last, deliberately. It is `1.0.<commit_count>`, so it changes on
# every commit — and an ARG/ENV invalidates every layer below it, which would
# rebuild dependencies, NIFs and assets on every build for nothing.
#
# The cost of declaring it here is that the compiled OTP `vsn` keeps mix.exs's
# default. That is only a fallback: the reported version comes from the
# `content.app_version` setting, which this ENV supplies at runtime and which
# takes precedence (see GamendWeb.ApiSpec.api_version/0).
ARG GAMEND_CONTENT_APP_VERSION
ENV GAMEND_CONTENT_APP_VERSION=${GAMEND_CONTENT_APP_VERSION}
RUN echo -n "${GAMEND_CONTENT_APP_VERSION}" > /app/VERSION

# ── Release assembly ──────────────────────────────────────────────────────
# Its own stage so the `full` target never pays for it: building the release
# takes time and would add ~430 MB of duplicated beams to an image that does
# not use it.
FROM builder AS release-build

RUN mix release --overwrite

# The plugin build above skips a missing plugins dir; the release stage copies
# it unconditionally, so make sure there is one to copy.
RUN mkdir -p "${GAMEND_CONTENT_PLUGINS_DIR}"

# ── Release runtime ───────────────────────────────────────────────────────
# gamend-runtime: openssl for ex_dtls, libsqlite3-0 for the Exqlite NIF,
# libstdc++6 and libncurses6 for ERTS itself, and GAMEND_HTTP_SERVER=true (a
# release starts no endpoint unless told to, see GamendWeb.HostRuntime's
# `── Releases ──` section). No compilers, no Rust, no source
# (docker/runtime/Dockerfile).
FROM ${RUNNER_IMAGE} AS release

# The adapter is chosen twice: baked in at compile time, and read again at
# runtime by GamendWeb.HostRuntime. They have to agree. Dropping this ARG on
# the floor leaves a Postgres-compiled image resolving SQLite defaults at boot,
# which Gamend.Repo's compile_env check catches as an abort — the right
# failure, but only if the value crosses the stage boundary at all.
ARG GAMEND_DB_ADAPTER
ARG GAMEND_CONTENT_PLUGINS_DIR
ARG GAMEND_CONTENT_APP_VERSION
ENV GAMEND_DB_ADAPTER=${GAMEND_DB_ADAPTER} \
    GAMEND_CONTENT_PLUGINS_DIR=${GAMEND_CONTENT_PLUGINS_DIR} \
    GAMEND_CONTENT_APP_VERSION=${GAMEND_CONTENT_APP_VERSION}

COPY --from=release-build /app/_build/prod/rel/gamend_host ./
COPY --from=release-build /app/VERSION ./VERSION

# The release reads its theme, markdown content and plugins relative to the
# directory it starts in, as `mix phx.server` does. None of them are part of
# the OTP release, so they come across on their own, to the paths the full
# image has them at.
COPY --from=release-build /app/theme ./theme
COPY --from=release-build /app/CHANGELOG.md /app/ROADMAP.md ./
COPY --from=release-build /app/blog ./blog
COPY --from=release-build /app/priv/docs ./priv/docs
COPY --from=release-build /app/${GAMEND_CONTENT_PLUGINS_DIR} ./${GAMEND_CONTENT_PLUGINS_DIR}

EXPOSE 4000 443

# gamend-runtime's start: the full target's, with the release's `eval`
# standing in for the mix tasks. It raises the open-files limit first (every
# WebSocket is a file descriptor), then Gamend.Release.prepare/0 creates the
# database when it can (a provisioned Postgres already has it, and its role
# may not be permitted to create one) and migrates, which is not allowed to
# fail.
CMD ["gamend-release-start", "gamend_host"]

# ── Full (default target) ─────────────────────────────────────────────────
# Last on purpose: `docker build .` with no --target builds the final stage,
# and this is the image that has always been the default.
FROM builder AS full

EXPOSE 4000 443

# gamend-builder's start: raise the file-descriptor limit, create the database
# if needed, then migrate and serve (docker/builder/bin/gamend-start).
CMD ["gamend-start"]
