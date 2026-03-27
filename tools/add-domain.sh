#!/bin/bash
[ "$1" = "" ] && cat "$(dirname $0)/../docs/help/add-domain.txt" && exit 1

cd "$(dirname $0)/../tree"

DOM="$1"
DIR="hosts-$1"
shift
if [ -e "$DIR" ]; then
    echo "Already exists: $DIR" >&2
    [ "$FORCE_ADD" = "" ] && exit 2
fi

mkdir -p "$DIR"
cd "$DIR"

ln -fs ../recipes/101_etc-hosts.jinja-sh .

cat <<tac >g8r.vars
host_domain=$DOM
tac
while [ "$1" != "" ]; do
    echo "$1" >>g8r.vars
    shift
done

cat <<tac >g8r.json
{
    "g8r_hosts": {}
}
tac

echo ADDED_DOMAIN_DIR=\"$(pwd)\"
echo ADDED_DOMAIN=\"${DOM}\"
