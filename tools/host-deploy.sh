#!/bin/bash
[ "${G8R_DEBUG:-n}" != "n" ] && set -x
G8R_HOME="${G8R_HOME:-$(cd "$(dirname "$0")"/.. && pwd)}"
set -euo pipefail
cd "$G8R_HOME"
PATH="$(pwd):$(pwd)/tools:$PATH"
export PATH G8R_HOME

target=$(g8r host-secret "${1:-}")
if [ "$target" = "" ]; then
    cat "docs/help/deploy.txt" >&2
    exit 1
fi

# shellcheck disable=SC1090,SC1091
source <(g8r host-cfg "$target")
vps_provider=${g8r_vps_provider:-linode}

exec tree/"$vps_provider"/deploy.sh "$target"
