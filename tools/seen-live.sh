#!/bin/bash
[ "${G8R_DEBUG:-n}" != "n" ] && set -x
cd "$(dirname $0)/.."
export PATH="$(pwd):$(pwd)/tools:$PATH"
set -e

HOST="$1"
R_IP="$2"

cd "exposed/hosts/$HOST"

R_IP="$(echo "$R_IP" |sed -e 's/^::ffff://')"
[ "$R_IP" = "" ] && exit 2

source g8r.vars
CHANGED=$(json_edit.py host.json "g8r_hosts/${host_name}/seen" = "$R_IP")
if [ "$CHANGED" != "" ]; then
    echo 'AUTOMATION: VARS_UPDATE'
    echo 'AUTOMATION: REBUILD'
fi
