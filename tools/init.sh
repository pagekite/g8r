#!/bin/bash
#
# Checks dependencies.
# Asks these questions:
#
#   1. What is the domain name for the hosts you are administering?
#   2. Do you already have a running web server for static content?
#   3. Where does your webserver read static content from? (A path)
#   4. What e-mail address will you use for server-admin related mail?
#   5. What is the public DNS domain name of this host?
#   6. Create /usr/bin/$g8r_helper helper?
#
# Create /usr/bin/$g8r_helper
# Create .../tree/hosts-domain/
# Configure the static web-server
#
[ "${G8R_DEBUG:-n}" != "n" ] && set -x

export G8R_HOME=${G8R_HOME:-"$(cd $(dirname $0)/..; pwd)"}
export G8R_TOOLS="$G8R_HOME/tools"
export G8R_TREE="$G8R_HOME/tree"

cd "${G8R_HOME}"
export PATH="$(pwd):$(pwd)/tools:$PATH"

cat <<tac >&2
##############################################################################

Oh hi! Welcome to the Governator!

This tool will ask a few questions to get you started.

If you need to pause for any reason, feel free to press CTRL+C and rerun
the script later. Your progress won't be lost.

Looks like your G8R_HOME is: ${G8R_HOME}
Hope that's OK.

Press ENTER to continue.

##############################################################################
tac
read


RANDCRAP=$(python3 -c \
  'import os,base64;print(str(base64.urlsafe_b64encode(os.urandom(16)),"utf-8")[:12])')

# These are the variables we are configuring
g8r_governating_domain=example.org
g8r_governator_hostname=g8r.example.org
g8r_admin_email=root@example.org
g8r_vps_provider=linode
g8r_init_have_webserver=N
g8r_init_static_path=/var/www/html
g8r_metrics_secret=$(python3 -c \
  'import os,base64;print(str(base64.urlsafe_b64encode(os.urandom(16)),"utf-8")[:12])' \
  2>/dev/null || echo governator)


# Load any previous progress...
OUTPUT="${G8R_TREE}/000_base.vars"
[ -e "$OUTPUT" ] && source "$OUTPUT"

# Guarantee we save on exit
save() {
    g8r_metrics_secret_bcrypt=$(htpasswd -nbBC 10 "" "$g8r_metrics_secret" 2>/dev/null |tr -d ':\n')
    cat <<tac >$OUTPUT
g8r_governating_domain=${g8r_governating_domain}
g8r_governator_hostname=${g8r_governator_hostname}
g8r_admin_email=${g8r_admin_email}
g8r_url_base=https://${g8r_governator_hostname}/g8r-${g8r_governating_domain}
g8r_vps_provider=${g8r_vps_provider}
g8r_metrics_secret=${g8r_metrics_secret}
g8r_metrics_password_bcrypt="${g8r_metrics_secret_bcrypt}"

g8r_init_have_webserver=${g8r_init_have_webserver}
g8r_init_static_path=${g8r_init_static_path}
tac
}
trap save EXIT


##############################################################################


echo -e '** Checking dependencies ...\n' >&2
MISSING=0
mcheck() {
    what=$1
    ok=$2
    if [ "$ok" = "" ]; then
        echo -e "\t${what}\tMISSING" >&2
        let MISSING=$MISSING+1
    else
        echo -e "\t${what}\tok" >&2
    fi
}
mcheck "make             " "$(which make)"
mcheck "htpasswd         " "$(which htpasswd)"
mcheck "python3          " "$(which python3)"
mcheck "rsync            " "$(which rsync)"
mcheck "python: jinja2   " "$(python3 -c 'import jinja2; print("ok")' 2>/dev/null)"
mcheck "python: markdown " "$(python3 -c 'import markdown; print("ok")' 2>/dev/null)"
mcheck "python: yaml     " "$(python3 -c 'import yaml; print("ok")' 2>/dev/null)"
if [ $MISSING = 0 ]; then
    for t in \
       "jinjatool        " \
       "automation_runner" \
       "update_variables " \
    ; do
        mcheck "$t" $(cd tools; python3 -c "import $t; print('ok')")
    done
fi
if [ $MISSING -gt 0 ]; then
    echo -e '\nUh, oh. Please fix that and retry!' >&2
    exit 1
else
    echo -e '\n** OK: Dependencies look good, off we go!' >&2
fi


##############################################################################


ask() {
    q=$1
    v=$2
    d=$3
    yn=$4
    echo >&2
    if [ "$yn" != "" ]; then
        echo -n "$q [$yn]: " >&2
    else
        echo    "$q" >&2
        echo -n "   [$d]: " >&2
    fi
    read answer
    [ "$answer" != "" ] && d="$answer"
    if [ "$yn" != "" ]; then
        case $d in
            Y*|y*) d=Y
            ;;
            *) d=N
            ;;
        esac
    fi
    echo "   OK, set $v=$d" >&2
    echo "$d"
}

g8r_governating_domain=$(ask \
    '1. What is the domain name for the hosts you are administering?' \
    g8r_governating_domain $g8r_governating_domain)

g8r_init_have_webserver=$(ask \
    '2. Do you already have a running web server for static content?' \
    g8r_init_have_webserver $g8r_init_have_webserver ${g8r_init_have_webserver:-y/N})

if [ "$g8r_init_have_webserver" = "N" ]; then
    cat <<tac >&1

##############################################################################

You're going to need a webserver:

   * Which is HTTPS enabled
   * Which is reachable from the public Internet
   * Which is configured to serve static files and follow symbolic links

We recommand Caddy: https://caddyserver.com/

Also, Pagekite if you want to run locally: https://pagekite.net/

tac
    exit 1
fi

g8r_init_static_path=$(ask \
    '3. Where does your webserver read static content from? (A path)' \
    g8r_init_static_path $g8r_init_static_path)

g8r_admin_email=$(ask \
    '4. What e-mail address will you use for server-admin related mail?' \
    g8r_admin_email $g8r_admin_email)

g8r_governator_hostname=$(ask \
    '5. What is the public DNS domain name of this host?' \
    g8r_governator_hostname $g8r_governator_hostname)

save && source $OUTPUT


##############################################################################


# Create g8r-$DOMAIN helper tool
g8r_helper=g8r-${g8r_governating_domain}
if [ -x "/usr/bin/$g8r_helper" ]; then
    echo >&2
    echo "6. Already exists: /usr/bin/$g8r_helper" >&2
else
    g8r_create_helper=$(ask \
        "6. Create /usr/bin/$g8r_helper helper?" g8r_create_helper Y Y/n)
    if [ "$g8r_create_helper" = "Y" ]; then
        cat <<tac >g8r-helper.tmp
#!/bin/sh
cd "$G8R_HOME" || exit 1
exec ./g8r "\$@"
tac
        chmod +x g8r-helper.tmp
        sudo mv g8r-helper.tmp /usr/bin/${g8r_helper} && (
            echo -n "   "
            ls -l /usr/bin/${g8r_helper}
        ) >&2
    fi
fi


# Create hosts-$DOMAIN in tree
echo >&2
g8r_hosts_dir="tree/hosts-${g8r_governating_domain}"
[ -d "${g8r_hosts_dir}" ] || source <("${G8R_TOOLS}"/add-domain.sh ${g8r_governating_domain})
echo "** OK: Created $ADDED_DOMAIN_DIR" >&2


# Create g8r-tools bundle in exposed/files
echo >&2
tar cfz exposed/files/g8r-tools.tar.gz g8r tools/*.py tools/{metrics,healthy,fragment-run}.sh
echo "** OK: Created: $(ls -1hs exposed/files/g8r-tools.tar.gz)" >&2


# Create the symbolic link for exposing things to the web
echo >&2
g8r_web_symlink="${g8r_init_static_path}/g8r-${g8r_governating_domain}"
if [ -d "$g8r_web_symlink" ]; then
    echo "** OK: Already exists: $g8r_web_symlink" >&2
else
    if [ -d "${g8r_init_static_path}" ]; then
        echo "** Creating: $g8r_web_symlink" >&2
        sudo ln -s "${G8R_HOME}/exposed" "$g8r_web_symlink"
    else
        echo "!! ERROR: Not found: ${g8r_init_static_path}" >&2
        exit 1
    fi
fi

# Test it...
TEST_FOR="$(date +%s).$$"
echo "$TEST_FOR" >"${G8R_HOME}/exposed/check.txt"
TEST_GOT="$(curl -s ${g8r_url_base}/check.txt)"
if [ ! "$TEST_FOR" = "$TEST_GOT" ]; then
    echo "!! ERROR: curl test failed for: ${g8r_url_base}/check.txt" >&2
    echo "   ${TEST_FOR} != ${TEST_GOT}"
    exit 2
else
    echo "** OK: curl test passed for: ${g8r_url_base}" >&2
    rm -f "${G8R_HOME}/exposed/check.txt"
fi


cat <<tac >&2

##############################################################################

All set!

We recommend creating a git branch: git checkout -b ${g8r_governating_domain}

Take care to NEVER push this branch to any public git forges, because
it contains secrets relating to your Governator setup.

Governator managed servers will download scripts from here:

    ${g8r_url_base}

You should now run \`git status\` to see which files and folders have been
added to your tree, CREATE A BRANCH, and commit the changes if you are happy.
Then add some servers!

##############################################################################
tac

