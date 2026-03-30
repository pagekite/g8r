#!/bin/bash
[ "$1" != "" ] || exit 1
exec $(dirname $0)/metrics.sh "$1_health" "$1_health" gauge $(date +%s)
