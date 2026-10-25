# Base images

What every Gamend image, and every host app built on Gamend, repeated in its
own Dockerfile, written once here and published to GHCR by core's CI
(`.github/workflows/base-images.yml`) for `linux/amd64` and `linux/arm64`, on
every push to `main` and weekly for Debian's security fixes.

| Image | Tag | What it is |
| --- | --- | --- |
| `ghcr.io/appsinacup/gamend-builder` | `elixir-1.20` | Elixir 1.20 on Debian 13, the system packages, Rust, Hex and Rebar, and the helpers below. The `builder` stage, and the `full` image itself |
| `ghcr.io/appsinacup/gamend-runtime` | `trixie` | Debian 13 with what an OTP release links against, and `gamend-release-start`. The `release` stage |
| `ghcr.io/appsinacup/gamend-backup` | `18` | Postgres 18 with the daily verified dump as its entrypoint (`backup/README.md`). The tag is the Postgres major, and has to be the database's |

Each also has `latest`. Core's own `Dockerfile` is built on the first two.

## An app's Dockerfile

Only the app's own steps stay in it:

```dockerfile
# syntax=docker/dockerfile:1
FROM ghcr.io/appsinacup/gamend-builder:elixir-1.20 AS builder
ARG MIX_ENV=prod
ENV MIX_ENV=${MIX_ENV}
COPY mix.exs mix.lock ./
RUN mix deps.get
COPY config config
RUN mix deps.compile
COPY . .
# Gamend from Hex is not in a checkout's mix.lock while it is a sibling path
# dependency, and COPY just replaced the lock deps.get wrote: lock it again.
RUN mix deps.get
RUN mix compile && mix assets.deploy && gamend-copy-static my_app --require

FROM builder AS release-build
RUN mix release --overwrite

FROM ghcr.io/appsinacup/gamend-runtime:trixie AS release
COPY --from=release-build /app/_build/prod/rel/my_app ./
CMD ["gamend-release-start", "my_app"]

FROM builder AS full
EXPOSE 4000 443
CMD ["gamend-start"]
```

A stage does not inherit another stage's `ENV`, so a value the release reads at
run time (the database adapter, the plugins directory) is declared again in the
`release` stage, as core's `Dockerfile` does.

## The helpers

In `gamend-builder` (`builder/bin/`):

| Command | Does |
| --- | --- |
| `gamend-build-plugins [flags]` | `mix deps.get`, `compile` and `plugin.bundle [flags]` in every plugin under `$GAMEND_CONTENT_PLUGINS_DIR`. `--no-deps` first skips the fetch |
| `gamend-copy-static <otp_app> [--require]` | copies the digested `priv/static` into `_build/$MIX_ENV/lib/<otp_app>/priv/static`, where Plug.Static and a release read it. Without `--require`, no digest (a dev build) is skipped |
| `gamend-start` | the `full` image's command: raises the open-files limit, rebuilds the plugins when `GAMEND_START_PLUGINS=1`, creates the database when it can, then `mix do db.migrate + phx.server` in one VM. `GAMEND_ERLANG_NODE=name@host` (with `RELEASE_COOKIE`) starts a named node |

In `gamend-runtime` (`runtime/bin/`):

| Command | Does |
| --- | --- |
| `gamend-release-start <release>` | raises the open-files limit, runs `Gamend.Release.prepare/0` (create when it can, migrate), then `bin/<release> start` |

## Changing one

A change here reaches an app at its next build: `docker compose build --pull`,
which every app's `rebuild.sh` runs, pulls the new tag. A package that is new on
GHCR is private until someone makes it public (the package's settings,
"Change visibility"), and a host pulling it anonymously gets `unauthorized`.

What belongs here is what every Gamend image needs. A package only one app uses
goes in that app's Dockerfile, on top of the builder.
