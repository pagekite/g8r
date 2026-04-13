#!/bin/bash
[ "${G8R_DEBUG:-n}" != "n" ] && set -x
cd "$(dirname $0)/.."
export PATH="$(pwd):$(pwd)/tools:$PATH"

[ "$1" = "" ] && cat "docs/help/add-domain.txt" && exit 1

cd tree
DOM="$1"
DIR="hosts-$1"
shift
if [ -e "$DIR" ]; then
    echo "Already exists: $DIR" >&2
    [ "$FORCE_ADD" = "" ] && exit 2
fi

mkdir -p "$DIR"
cd "$DIR"

ln -fs ../recipes/config-cache.jinja-* ../recipes/101_etc-hosts.jinja-sh .

cat <<tac >000_base.vars
host_domain=$DOM
tac
while [ "$1" != "" ]; do
    echo "$1" >>000_base.vars
    shift
done

cat <<tac >002_config.json
{
    "g8r_service_domains": {}
}
tac

cat <<tac >009_automation.json
{
    "g8r_hosts": {},
    "g8r_update_schedule": {}
}
tac

echo ADDED_DOMAIN_DIR=\"$(pwd)\"
echo ADDED_DOMAIN=\"${DOM}\"
