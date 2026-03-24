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
# Create git branch
# Create /usr/bin/$g8r_helper
# Create .../tree/hosts-domain/
# Configure the static web-server
#
export G8R_HOME=${G8R_HOME:-"$(cd $(dirname $0)/..; pwd)"}
export G8R_TOOLS="$G8R_HOME/tools"
export G8R_TREE="$G8R_HOME/tree"
cd $G8R_HOME

##############################################################################

# These are the variables we are configuring
g8r_governating_domain=example.org
g8r_governator_hostname=g8r.example.org
g8r_admin_email=root@example.org
g8r_init_have_webserver=N
g8r_init_static_path=/var/www/html

# Load any previous progress...
OUTPUT="${G8R_TREE}/g8r.vars"
[ -e "$OUTPUT" ] && source "$OUTPUT"

# Guarantee we save on exit
save() {
    cat <<tac >$OUTPUT
g8r_governating_domain=${g8r_governating_domain}
g8r_governator_hostname=${g8r_governator_hostname}
g8r_admin_email=${g8r_admin_email}
g8r_url_base=https://${g8r_governator_hostname}/g8r

g8r_init_have_webserver=${g8r_init_have_webserver}
g8r_init_static_path=${g8r_init_static_path}
tac
}
trap save EXIT


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
mcheck "python3          " "$(which python3)"
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
    echo -e '\n** Dependencies look good, off we go!' >&2
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


# Set up git branch for this setup
echo >&2
echo "** Creating and activating git branch: ${g8r_governating_domain}" >&2
git branch "${g8r_governating_domain}" >/dev/null 2>&1
echo -n "** " >&1
git checkout "${g8r_governating_domain}" >/dev/null || exit 1 


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
cd $G8R_HOME || exit 1
git checkout ${g8r_governating_domain} || exit 2
echo "==[ ${g8r_governating_domain} : \$(pwd) ]==" >&2
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
mkdir -p "${g8r_hosts_dir}"
touch "${g8r_hosts_dir}/g8r.vars"
echo "** Created \$G8R_HOME/${g8r_hosts_dir}" >&2


# Create the symbolic link for exposing things to the web
echo >&2
g8r_web_symlink="${g8r_init_static_path}/g8r-${g8r_governating_domain}"
if [ -d "$g8r_web_symlink" ]; then
    echo "** Already exists: $g8r_web_symlink" >&2
else
    if [ -d "${g8r_init_static_path}" ]; then
        echo "** Creating: $g8r_web_symlink" >&2
        sudo ln -s "$G8R_HOME/exposed" "$g8r_web_symlink"
    else
        echo "!! Not found! ${g8r_init_static_path}" >&2
        exit 1
    fi
fi


cat <<tac >&2

##############################################################################

All set!

This g8r repo has a new branch named: ${g8r_governating_domain}

Take care to NEVER push this branch to any public git forges, because
it contains secrets relating to your Governator setup.

Governator managed servers will download scripts from here:

    ${g8r_url_base}

You should now run \`git status\` to see which files and folders have been
added to your tree, and commit the changes if you are happy. Then add some
servers!

##############################################################################
tac

