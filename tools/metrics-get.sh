#!/bin/bash
[ "${G8R_DEBUG:-n}" != "n" ] && set -x
cd "$(dirname $0)/.."
export PATH="$(pwd):$(pwd)/tools:$PATH"

HOSTS="$*"
RAW_METRICS="${RAW_METRICS:-n}"

FILTERS="${FILTERS:-g8r}"
[ "$FILTERS" = '*' ] && FILTERS=""

source tree/g8r.vars
if [ "$1" = "-a" ]; then
    shift
    HOSTS="$*"
    for hd in $(find tree -type f -name 102_metrics.sh |cut -d/ -f1-3); do
        HOSTS="$(cd $hd; source ../g8r.vars; source g8r.vars; echo $host_name.$host_domain) $HOSTS"
    done
fi

if [ "$HOSTS" = "" ]; then
    if [ -e "${G8R_HOME}/scripts/" ]; then
        HOSTS=$(hostname --fqdn)
    else
        cat "$(dirname $0)/../docs/help/metrics.txt"
        exit 1
    fi
fi

[ "$RAW_METRICS" != "n" ] || echo -n '{'
for h in $HOSTS; do
    if [ "$RAW_METRICS" != "n" ]; then
        echo "# Metrics from $h"
        curl -s "http://governator:${g8r_metrics_secret}@$h:1987/metrics"
        echo
    else
        metrics_to_json.py "$h:1987" \
            -w "$h" -u governator -p "${g8r_metrics_secret}" \
            $FILTERS
    fi
done
[ "$RAW_METRICS" != "n" ] || echo '"EOF":1}'
