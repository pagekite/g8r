#!/bin/bash
[ "${G8R_DEBUG:-n}" != "n" ] && set -x
cd "$(dirname $0)/.."
export PATH="$(pwd):$(pwd)/tools:$PATH"

if [ "$1" = "-A" ]; then
    LIVE_METRICS=y RAW_METRICS=y tools/metrics-get.sh -a >/dev/null
    LIVE_METRICS=n RAW_METRICS=n tools/metrics-get.sh -a >tree/status/metrics.json
    echo 'AUTOMATION: VARS_UPDATE'
    echo 'AUTOMATION: REBUILD'
    exit 0
fi

HOSTS="$*"
export LIVE_METRICS="${LIVE_METRICS:-n}"
export RAW_METRICS="${RAW_METRICS:-n}"

FILTERS="${FILTERS:-g8r}"
[ "$FILTERS" = '*' ] && FILTERS=""

source tree/000_base.vars
if [ "$1" = "-a" ]; then
    shift
    HOSTS="$*"
    DEADLINE=$(date +%s --date '2 hours ago')
    for hd in $(find tree -type f -name 102_metrics.sh |cut -d/ -f1-3); do
        SECRET=$(echo "$hd" |cut -d/ -f3)
        SEEN=$(jq .status.\"$SECRET\".seen.when tree/status/summary.json)        
        if [ "$SEEN" != null ]; then
            H="$(source <(g8r host-cfg "$SECRET"); echo $host_name.$host_domain)"
            if [ "$HOSTS" = "" ]; then
                HOSTS="$H"
            else
                HOSTS="$H $HOSTS"
            fi
        fi
    done
fi

if [ "$HOSTS" = "" ]; then
    if [ -e "${G8R_HOME}/scripts/" ]; then
        HOSTS=$(hostname --fqdn)
    else
        cat "$(dirname $0)/../docs/help/metrics.txt" >2
        exit 1
    fi
fi

[ "$RAW_METRICS" != "n" ] || echo -n '{"metrics": {'
(for h in $HOSTS; do
    SRC="$h:1987"
    RAW_CACHE=tree/status/host-"$h".omtxt
    if [ "$LIVE_METRICS" != "y" -a -e "$RAW_CACHE" ]; then
        if [ $(stat -c %X "$RAW_CACHE") -gt $(date +%s --date '2 hours ago') ]; then
            SRC="$RAW_CACHE"
        else
            LIVE_METRICS=y
        fi
    else
        LIVE_METRICS=y
    fi

    if [ "$RAW_METRICS" != "n" ]; then
        echo "# Metrics from $h"
        if [ "$LIVE_METRICS" != "y" ]; then
            cat "$RAW_CACHE"
        else
            curl --max-time 10 -s \
                "http://governator:${g8r_metrics_secret}@$h:1987/metrics" \
                |tee "$RAW_CACHE".new
            [ -s "$RAW_CACHE".new ] \
             && mv -f "$RAW_CACHE".new "$RAW_CACHE" \
             || rm -f "$RAW_CACHE".new
        fi
        echo
    fi
    if [ "$RAW_METRICS" = "n" ]; then
        metrics_to_json.py $SRC \
            -w "$h" -u governator -p "${g8r_metrics_secret}" \
            $FILTERS
    fi
done) |sed -e '$,$s/,$//'
[ "$RAW_METRICS" != "n" ] || echo '}}'
