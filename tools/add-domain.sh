#!/bin/bash
[ "$1" = "" ] && cat "$(dirname $0)/../docs/help/add-domain.txt" && exit 1

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
