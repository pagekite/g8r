#!/bin/bash
[ "${G8R_DEBUG:-n}" != "n" ] && set -x
cd "$(dirname $0)/.."
export PATH="$(pwd):$(pwd)/tools:$PATH"
set -e

HOST="$1"
R_IP="$(echo "$2" |sed -e 's/^::ffff://')"
[ "$R_IP" = "" ] && exit 2

CHANGED=$(json_edit.py tree/status/summary.json \
    "${HOST}/seen/when" = "$(date +%s)" \
    "${HOST}/seen/ip" = "$R_IP")

if [ "$CHANGED" != "" ]; then
    echo 'AUTOMATION: VARS_UPDATE'
    echo 'AUTOMATION: REBUILD'
fi
