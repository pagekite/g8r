#!/bin/bash
[ "$1" = "" ] && cat <<tac && exit 1
Usage: g8r add-domain <domain.tld> [var=val ...]

Add a new domain to your Governator for management, optionally setting
global domain varibles at the same time.

Examples:

    g8r add-domain foo.com g8r_sshd_port=23 g8r_always_install="screen git"

tac

cd "$(dirname $0)/../tree"

DOM="$1"
DIR="hosts-$1"
shift
if [ -e "$DIR" ]; then
    echo "Already exists: $DIR"
    [ "$FORCE_ADD" = "" ] && exit 2
fi

mkdir -p "$DIR"

cat <<tac >"$DIR/g8r.vars"
host_domain=$DOM
tac
while [ "$1" != "" ]; do
    echo "$1" >>"$DIR/g8r.vars"
    shift
done

cat <<tac >"$DIR/g8r.json"
{
    "g8r_hosts": {}
}
tac
