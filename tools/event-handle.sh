#!/bin/bash
[ "${G8R_DEBUG:-n}" != "n" ] && set -x
set -e
G8R_HOME="${G8R_HOME:-$(cd "$(dirname "$0")"/.. && pwd)}"
cd "$G8R_HOME"
PATH="$(pwd):$(pwd)/tools:$PATH"
export PATH G8R_HOME

EVENT="$1"
HOST=${2//./-}
if [ "$HOST" = "" ]; then
    echo "Usage: $0 <event> <host> [<ip> [<log-time>]]" >&2
    exit 1
fi
if ! cd tree/hosts-*/"$HOST" 2>/dev/null; then
    echo "Unknown host: $HOST" >&2
    exit 2
fi
# shellcheck disable=SC1090,SC1091
source <(g8r host-cfg "$HOST")
cd "$G8R_HOME"

R_IP="$(echo "$3" | sed -e 's/^::ffff://; s/[^a-fA-F0-9:\.]//g')"
L_TS="$(echo "$4" | sed -e 's/:/ /; s,/, ,g')"

if [ "$L_TS" != "" ] && [ "$NOW" = "" ]; then
    NOW=$(date +%s --date "$L_TS")
fi
NOW=${NOW:-$(date +%s)}

# All events update /seen/
if [ "$R_IP" != "" ]; then
    CHANGED=$(json_edit.py tree/status/host-"${HOST}".json \
        "status/${HOST}/seen/when" = "$NOW" \
        "status/${HOST}/seen/ip" = "$R_IP")
fi

# Custom functionality
case "$EVENT" in
    drain)
        CHANGED=$(json_edit.py tree/status/host-"${HOST}".json \
            "status/${HOST}/drained/when" = "$NOW" \
            "status/${HOST}/drained/ip" = "$R_IP")
        ;;
    undrain)
        CHANGED=$(json_edit.py tree/status/host-"${HOST}".json \
            "status/${HOST}" rm "drained")
        ;;
esac

# All events get logged, except the seen event
if [ "$EVENT" != "seen" ]; then
    # shellcheck disable=SC2034
    CHANGED=$(json_edit.py tree/status/events.json \
        "LATEST/ANY" max "$NOW" \
        "LATEST/${EVENT}" max "$NOW" \
        "log" add "[$NOW, \"$HOST\", \"$EVENT\"]" \
        "log" bound "${g8r_eventlog_max:-50}" \
        "log" sort 1)
fi

cat <<tac
AUTOMATION: VARS_UPDATE
AUTOMATION: REBUILD
tac
