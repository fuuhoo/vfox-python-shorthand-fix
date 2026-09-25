#!/usr/bin/env bash
# Run the fix verification in a container (no network needed inside).
#
#   ./test.sh                # default harness image, host arch
#   ./test.sh <image>        # your own image with vfox + the python plugin
#   RUN_PLATFORM=linux/amd64 ./test.sh
#
# The default image ships vfox 1.0.12 with python 3.9.25 and 3.12.14 installed,
# which is the state the checks assume. Any image works as long as `vfox list`
# shows two python patch versions from different minor releases.
#
# Files are copied in with `docker cp` rather than bind-mounted, because macOS
# file sharing settings regularly deny container reads of mounted home dirs.
set -uo pipefail

IMAGE="${1:-registry.cn-qingdao.aliyuncs.com/fubin/vfox-full:1.0.12}"
RUN_PLATFORM="${RUN_PLATFORM:-}"
P=(); [ -n "$RUN_PLATFORM" ] && P=(--platform "$RUN_PLATFORM")

cd "$(dirname "${BASH_SOURCE[0]}")"
cid=$(docker create -i "${P[@]+"${P[@]}"}" --entrypoint bash "$IMAGE" /fix/test/in-container.sh)
trap 'docker rm -f "$cid" >/dev/null 2>&1 || true' EXIT
docker cp . "$cid":/fix
docker start -a "$cid"
