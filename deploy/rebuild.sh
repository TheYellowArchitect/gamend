#!/usr/bin/env bash
# Deploy this checkout on the host it runs on: pull it, then run Gamend's
# deploy script (deploy/gamend-deploy in github.com/appsinacup/gamend) at the
# version this app's deploy.conf names, GAMEND_DEPLOY_REF: a commit is
# fetched once and kept, a branch every time. Every app has this same file;
# the original is Gamend's deploy/rebuild.sh, and deploy/README.md there says
# what goes in deploy.conf.
#
#   ./rebuild.sh            pull, check, build, start, prune
#   ./rebuild.sh --check    pull, then the checks alone
#   ./rebuild.sh --no-pull  deploy what is checked out now
#
# GAMEND_DEPLOY=/path/to/gamend-deploy runs that file instead (to try a change).
set -euo pipefail
cd "$(dirname "$0")"

# Pulled first, so the checks and the deploy are the new code's.
case " $* " in
  *" --no-pull "*) ;;
  *) git pull --ff-only ;;
esac

tool=${GAMEND_DEPLOY:-}
if [ -z "$tool" ]; then
  ref=$(sed -n 's/^GAMEND_DEPLOY_REF=//p' deploy.conf | tr -d "\"' ")
  ref=${ref:-main}
  dir="${XDG_CACHE_HOME:-$HOME/.cache}/gamend-deploy/${ref}"
  tool="${dir}/gamend-deploy"
  if [ ! -x "$tool" ] || ! [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then
    mkdir -p "$dir"
    curl -fsSL "https://raw.githubusercontent.com/appsinacup/gamend/${ref}/deploy/gamend-deploy" -o "${tool}.part"
    chmod +x "${tool}.part"
    mv "${tool}.part" "$tool"
  fi
fi

exec "$tool" "$@"
