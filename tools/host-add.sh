#!/bin/bash
[ "${G8R_DEBUG:-n}" != "n" ] && set -x
G8R_HOME="${G8R_HOME:-$(cd $(dirname $0)/.. && pwd)}"
cd "$G8R_HOME"
export PATH="$(pwd):$(pwd)/tools:$PATH"

cd tree || exit 100
source 000_base.vars
[ "$1" = "" -o "$2" = "" -o ! -d "skeletons/$2" ] && cat "../docs/help/add-host.txt" && exit 1 || true

G8R_TREE="$(pwd)"

HOST_NAME="$1"
HOST_TYPE="$2"
HOST_DOMAIN="${3:-$g8r_governating_domain}"
HOST_RANDCRAP=$(python3 -c \
  'import os,base64;print(str(base64.urlsafe_b64encode(os.urandom(16)),"utf-8")[:12])')
HOST_SECRET="${HOST_TYPE}-${HOST_NAME}-${HOST_RANDCRAP}"

DIR="hosts-${HOST_DOMAIN}/$HOST_SECRET"
EXISTING=$(cd hosts-${HOST_DOMAIN}; ls -1 |grep "${HOST_TYPE}-${HOST_NAME}")
if [ "$EXISTING" != "" ]; then
    echo "Already exists: $EXISTING" >&2
    [ "$FORCE_ADD" = "" ] && exit 2
fi
set -e

mkdir -p "$DIR" || exit 2
cd "$DIR"
DIR="$(pwd)"

HOST_INDEX=$(cd ..; ls -1 */host.json |wc -l)

cp -a "../../skeletons/${HOST_TYPE}/." .
cat <<tac >000_base.vars
host_name=${HOST_NAME}
host_type=${HOST_TYPE}
host_index=${HOST_INDEX}
host_ipv4=$IPv4
host_ipv6=$IPv6
host_updates="${HOST_UPDATES:-default}"
host_update_schedule="${HOST_UPDATE_SCHEDULE:-weekly}"
host_backups="${BACKUPS:-tgz:auto}"
host_g8r_secret=${HOST_SECRET}
tac

json_edit.py \
    host.json \
       "g8r_hosts/${HOST_NAME}/secret" = "${HOST_SECRET}" \
       "g8r_hosts/${HOST_NAME}/type" = "${HOST_TYPE}" \
       "g8r_hosts/${HOST_NAME}" remove "ipv4" \
       "g8r_hosts/${HOST_NAME}" remove "ipv6" >/dev/null

if [ "$IPv4" != "" ]; then
    json_edit.py \
        host.json \
            "g8r_hosts/${HOST_NAME}/ipv4" append "${IPv4}" >/dev/null
fi
if [ "$IPv6" != "" ]; then
    json_edit.py \
        host.json \
            "g8r_hosts/${HOST_NAME}/ipv6" append "${IPv6}" >/dev/null
fi

cd "$G8R_TREE/../exposed/hosts" || exit 3
ln -fs "$DIR" . || exit 4

echo ADDED_HOST_DIR=\"$DIR\"
echo ADDED_HOST_SECRET=\"${HOST_SECRET}\"
echo ADDED_HOST_TYPE=\"${HOST_TYPE}\"
echo ADDED_HOST_NAME=\"${HOST_NAME}\"
if [ ! "$ADD_CANARY" = "" ]; then
    cd "$G8R_TREE/canaries"
    ln -s "$DIR" .
    echo ADDED_CANARY=\"${HOST_SECRET}\"
fi
