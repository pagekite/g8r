#!/bin/bash
cd "$(dirname $0)/../tree" || exit 100
source g8r.vars
[ "$1" = "" -o "$2" = "" -o ! -d "skeletons/$2" ] && cat "../docs/help/add-host.txt" && exit 1

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

mkdir -p "$DIR" || exit 2
cd "$DIR"
DIR="$(pwd)"

cp -a "../../skeletons/${HOST_TYPE}/." .
cat <<tac >g8r.vars
host_name=${HOST_NAME}
host_type=${HOST_TYPE}
host_ipv4=$IPv4
host_ipv6=$IPv6
host_g8r_secret=${HOST_SECRET}
tac
[ "$IPv4" != "" ] && IPv4="\"$IPv4\""
[ "$IPv6" != "" ] && IPv6="\"$IPv6\""
cat <<tac >host.json
{
  "g8r_hosts": {
    "${HOST_NAME}": {
       "ipv4": [${IPv4}],
       "ipv6": [${IPv6}],
       "type": "${HOST_TYPE}"
    }
  }
}
tac

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
