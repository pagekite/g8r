#!/bin/bash
[ "${G8R_DEBUG:-n}" != "n" ] && set -x
set -e
G8R_SCRIPT="$1"
G8R_FRAGMENT="$2"

if [ -x "$G8R_SCRIPT" -a "$G8R_FRAGMENT" != "" ]; then

    export G8R_FRAGMENT
    sed -e "0,/^$/ p; \
            /BEGIN_G8R_${G8R_FRAGMENT}/,/END_G8R_${G8R_FRAGMENT}/ p; \
            d" \
      <"$G8R_SCRIPT" \
      |bash

    exit 0
else
    cat <<tac >&2
Usage: $0 </path/to/script.sh> <fragment>

This will run the named script fragment from within script.sh.

If you are seeing this you either didn't specify enough arguments, or
the script you've requested does not exist. Note that a fragment not
existing within a script is not considered a problem.

Script fragments are delimited by lines containing the strings
BEGIN_G8R_fragment and END_G8R_fragment preceded by the first
non-blank lines of the script, which are considered part of all
fragments.

The environment variable G8R_FRAGMENT will be set to the fragment
name when the fragment runs.
tac
    exit 1
fi

## BEGIN_G8R_TEST ##
echo "This is the TEST fragment - '$G8R_FRAGMENT' and '$G8R_SCRIPT' should be blank."
if [ "$G8R_FRAGMENT" != "" -o "$G8R_SCRIPT" != "" ]; then
    echo "Oops, test failed"
    exit 1
else
    echo "OK, cool."
fi
## END_G8R_TEST ##
