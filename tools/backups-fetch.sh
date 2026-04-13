#!/bin/bash
[ "${G8R_DEBUG:-n}" != "n" ] && set -x
G8R_HOME="${G8R_HOME:-$(cd $(dirname $0)/.. && pwd)}"
cd "$G8R_HOME"
export PATH="$(pwd):$(pwd)/tools:$PATH"
set -e

if [ "$1" = "" ]; then
    cat "$G8R_HOME/docs/help/backups.txt"
    exit 1
fi
if [ "$1" = "-a" ]; then
    for HOST in $("$G8R_HOME"/g8r hosts |awk '{print $4}'); do
        backups-fetch.sh "$HOST" || true
    done
    exit 0
fi

for TARGET_HOST in $*; do
    TARGET_SECRET=$(g8r host-secret "$TARGET_HOST")
    if ! cd "$G8R_HOME"/tree/hosts-*/"$TARGET_SECRET" 2>/dev/null ; then
        echo "Unknown host: $TARGET_HOST"
        exit 1
    fi
done


for TARGET_HOST in $*; do
    source <(g8r host-cfg "$TARGET_HOST")
    [ "${host_g8r_secret}" = "" ] && exit 2

    TARGET_HOSTNAME="${host_name}.${host_domain}"
    TARGET_DIR="$G8R_HOME"/exposed/files/backups/"${host_g8r_secret}"
    mkdir -p "$TARGET_DIR"
    cd "$TARGET_DIR"

    rsync -a --rsh="ssh -p ${g8r_sshd_port:-22} -o ConnectTimeout=5" \
      root@"$TARGET_HOSTNAME":/var/lib/g8r/backups/. .

    TOTAL_FILES=0
    TOTAL_BYTES=0
    TOTAL_MTIME=0
    for backup in *.tgz; do
        BYTES=$(stat -c %s "$backup")
        MTIME=$(stat -c %X "$backup")
        let TOTAL_BYTES=$TOTAL_BYTES+$BYTES
        let TOTAL_FILES=$TOTAL_FILES+1
        [ "$MTIME" -gt "$TOTAL_MTIME" ] && TOTAL_MTIME=$MTIME
        json_edit.py manifest-new.json \
            "g8r_backups/$TARGET_HOST/TOTALS/ts" = $TOTAL_MTIME \
            "g8r_backups/$TARGET_HOST/TOTALS/bytes" = $TOTAL_BYTES \
            "g8r_backups/$TARGET_HOST/TOTALS/count" = $TOTAL_FILES \
            "g8r_backups/$TARGET_HOST/$backup/bytes" = $BYTES \
            "g8r_backups/$TARGET_HOST/$backup/ts" = $MTIME \
            >/dev/null
    done

    if [ "$(md5sum <manifest-new.json)" != "$(md5sum <manifest.json 2>/dev/null || true)" ]; then
        mv -f manifest-new.json manifest.json
    else
        rm -f manifest-new.json
    fi
done
echo 'AUTOMATION: VARS_UPDATE'
