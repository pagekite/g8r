#!/bin/bash
[ "${G8R_DEBUG:-n}" != "n" ] && set -x
set -e
G8R_HOME="${G8R_HOME:-$(cd "$(dirname "$0")"/.. && pwd)}"
G8R_TREE="$G8R_HOME"/tree
cd "$G8R_HOME"
PATH="$(pwd):$(pwd)/tools:$PATH"
export PATH G8R_HOME G8R_TREE


cd tree
# shellcheck disable=SC1090,SC1091
source 000_base.vars

if [ "$1" = "" ] || [ "$2" = "" ] || [ ! -d "skeletons/$2/." ]; then
    cat "$G8R_HOME/docs/help/add-host.txt" >&2
    exit 1
fi

HOST_NAME="$1"
HOST_TYPE="$2"
HOST_DOMAIN="${3:-$g8r_governating_domain}"
HOST_RANDCRAP=$(python3 -c \
    'import os,base64;print(str(base64.urlsafe_b64encode(os.urandom(16)),"utf-8")[:12])')
HOST_SECRET="${HOST_TYPE}-${HOST_NAME}-${HOST_RANDCRAP}"

HOST_DIR="hosts-${HOST_DOMAIN}/$HOST_SECRET"
# shellcheck disable=SC2010
EXISTING=$(
    cd hosts-"$HOST_DOMAIN"
    ls -1 | grep "${HOST_TYPE}-${HOST_NAME}-" || true
)
if [ "$EXISTING" != "" ]; then
    echo "Already exists: $EXISTING" >&2
    [ "$FORCE_ADD" = "" ] && exit 2
fi
set -e

mkdir -p "$HOST_DIR" || exit 2
cd "$HOST_DIR"
# shellcheck disable=SC2012
HOST_INDEX=$(cd .. && ls -1d -- */host.json 2>/dev/null | wc -l || echo 0)
HOST_DIR="$(pwd)"

cp -a "../../skeletons/${HOST_TYPE}/." .
cat <<tac >>000_base.vars
host_name='${HOST_NAME}'
host_type='${HOST_TYPE}'
host_index='${HOST_INDEX}'
host_updates='${HOST_UPDATES:-default}'
host_update_schedule='${HOST_UPDATE_SCHEDULE:-weekly}'
host_backups='${BACKUPS:-tgz:auto}'
host_g8r_secret='${HOST_SECRET}'
tac

[ -e "009_automation.json" ] || echo '{}' >009_automation.json

json_edit.py \
    host.json \
    "g8r_hosts/${HOST_NAME}/secret" = "${HOST_SECRET}" \
    "g8r_hosts/${HOST_NAME}/type" = "${HOST_TYPE}" \
    "g8r_hosts/${HOST_NAME}" remove "ipv4" \
    "g8r_hosts/${HOST_NAME}" remove "ipv6" >/dev/null

# shellcheck disable=SC2154
if [ "$IPv4" != "" ]; then
    json_edit.py \
        host.json \
        "g8r_hosts/${HOST_NAME}/ipv4" append "$IPv4" >/dev/null
fi
# shellcheck disable=SC2154
if [ "$IPv6" != "" ]; then
    json_edit.py \
        host.json \
        "g8r_hosts/${HOST_NAME}/ipv6" append "$IPv6" >/dev/null
fi

cd "$G8R_TREE/../exposed/hosts" || exit 3
ln -fs "$HOST_DIR" . || exit 4

cat <<tac
ADDED_HOST_DIR='$HOST_DIR'
ADDED_HOST_SECRET='$HOST_SECRET'
ADDED_HOST_TYPE='$HOST_TYPE'
ADDED_HOST_NAME='$HOST_NAME'
tac
if [ ! "$ADD_CANARY" = "" ]; then
    cd "$G8R_TREE/canaries"
    [ -e "$HOST_DIR" ] || ln -s "$HOST_DIR" .
    echo "ADDED_CANARY='$HOST_SECRET'"
fi
