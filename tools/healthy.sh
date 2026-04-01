#!/bin/bash
[ "$1" != "" ] || exit 1
exec $(dirname $0)/metrics.sh "$1_healthy" "$1_healthy" gauge $(date +%s)
