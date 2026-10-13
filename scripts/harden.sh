#!/usr/bin/env bash
# Harden the design with LibreLane (Classic flow) in its Docker image.
#
#   scripts/harden.sh [run_tag]
#
# Env: LIBRELANE_IMAGE (default ghcr.io/librelane/librelane:3.0.14)
#      PDK_ROOT        (default ~/.ciel; sky130 8afc8346 enabled with ciel)
#      CPUS            (default 4)
# The flow runs at the lowest CPU and I/O priority so a shared desktop stays
# responsive. Results land in librelane/runs/<run_tag>/ (gitignored).
set -euo pipefail
IMAGE=${LIBRELANE_IMAGE:-ghcr.io/librelane/librelane:3.0.14}
PDK_ROOT=${PDK_ROOT:-$HOME/.ciel}
CPUS=${CPUS:-4}
TAG=${1:-run-$(date +%Y%m%d-%H%M%S)}
REPO=$(cd "$(dirname "$0")/.." && pwd)

cid=$(docker run -d --cpus="$CPUS" -u "$(id -u):$(id -g)" -e HOME=/tmp \
      -v "$REPO:$REPO" -v "$PDK_ROOT:$PDK_ROOT" -w "$REPO" --entrypoint "" "$IMAGE" \
      sh -c "sleep 2; exec nice -n 19 librelane --pdk-root '$PDK_ROOT' --run-tag '$TAG' librelane/config.json")
# The container's processes run as us, so we can drop them to idle I/O class.
pid=$(docker inspect -f '{{.State.Pid}}' "$cid")
ionice -c3 -p "$pid" 2>/dev/null || true
echo "container $cid (pid $pid), run tag $TAG"
docker logs -f "$cid"
rc=$(docker wait "$cid")
docker rm "$cid" >/dev/null
exit "$rc"
