#!/bin/bash
[ "${G8R_DEBUG:-n}" != "n" ] && set -x
cd "$(dirname $0)/.."
export PATH="$(pwd):$(pwd)/tools:$PATH"

target=$(g8r host-secret "$1")
[ "$target" = "" ] && cat "docs/help/deploy.txt" && exit 1 || true

source <(g8r host-cfg "$target")
vps_provider=${g8r_vps_provider:-linode}

exec tree/"$vps_provider"/deploy.sh $target
