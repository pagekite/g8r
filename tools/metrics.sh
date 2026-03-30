#!/bin/bash
METRIC_GROUP="$1"
shift

[ "$METRIC_GROUP" != "" ] || exit 1
cd /var/lib/prometheus/node-exporter || exit 2

echo >g8r_${METRIC_GROUP}.prom.tmp
while [ "$3" != "" ]; do
    METRIC="$1"
    MTYPE="$2"
    MVAL="$3"
    cat <<tac >"g8r_${METRIC_GROUP}.prom.tmp"
# HELP g8r_${METRIC} This is a Governator metric 
# TYPE g8r_${METRIC} ${MTYPE}
g8r_${METRIC} ${MVAL}

tac
    shift; shift; shift
done
mv -f "g8r_${METRIC_GROUP}.prom.tmp" "g8r_${METRIC_GROUP}.prom"
