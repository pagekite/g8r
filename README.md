# Governator - g8r

curl|bash your servers into submission!

**PROJECT STATUS:** Pre-Alpha. Do Not Use.

## What's this?

<img src="docs/imgs/Governator-by-Kria.png" alt="" width="35%" align=right>

This is (or will be) a framework and collection of minimalist tools which make it easy to provision and manage a modest fleet of (VPS) servers.

Governator sits somewhere between configuration managment (like Ansible)
and orchestration (like Kubernetes).
Like Ansible (or Puppet, or Chef),
Governator describes how to configure and/or update a fleet of servers.
Dabbling in orchestration,
g8r also has opinions on how to implement CI/CD workflows,
backups,
monitoring,
and routine system upgrades and updates over time.

Rather than create a whole suite of tools to describe,
implement and deploy server configurations,
g8r mainly uses shell scripts and web technology.

The code which provisions or updates any given server is a collection of small shell scripts.
These scripts are generated and organized using the exact same techniques as a static website generator:
a tree of content,
combining templates (Jinja2) and variables
(shell, YAML or JSON)
to generate shell scripts (/bin/sh instead of HTML).

Similarly,
rather than pushing instructions to the targets using ssh or a custom protocol,
servers pull their management scripts,
custom binaries (including docker images) and auxillary data from a static HTTP server.
Using curl, wget or any other standard tool.
Whether new updates need to be downloaded and applied (or not) is communicated using HTTP's existing vocabulary for checking for content updates.

There are a few keys to making this work:

   1. Security: URLs must be unguessable, unshared and served over HTTPS
   2. Symbolic links allow hosts to share templates
   3. Shell scripts install shell scripts that run shell scripts
   4. Updates are scheduled by:
      * cron
      * a custom tool reacting to something exciting in a log file
      * an impatient human

The goal of this repo is to help get you started with some working examples,
and document what rules to follow when you make your own updates.


## Getting Started

To get started,
decide where you will run the Governator Server
(a static web server with this repo installed).

Pick a folder (and user) for your Governator,
check out this repo and run the init script:

    git clone https://github.com/pagekite/g8r
    cd g8r
    ./g8r init

The tool will ask the following questions:

   1. What is the domain name for the hosts you are administering?
   2. Do you already have a running web server for static content?
   3. Where does your webserver read static content from? (A path)
   4. What e-mail address will you use for server-admin related mail?
   5. What is the public DNS domain name of this host?
   6. Create /usr/bin/$g8r_helper helper?

If you would rather configure things by hand,
the source of [tools/init.sh](tools/init.sh) should be relatively easy to read.

**Note:** If you don't have a public IP address and DNS name,
or just want to run this off a laptop or other personal computer,
you can use <https://pagekite.net/> to expose your Governator Server to the web.
In this case,
you will provide your `kitename.pagekite.me` domain name as the answer to question 5 above.
Note that managed servers will only be able to update themselves when the Governator Server is online.


### Using the g8r tool

If you said yes to question 6 when running `g8r init`,
there will be a `g8r-example.org` tool on your path which you can run to manage your Governated servers.
In the examples below we use `./g8r` to do the same thing.

Run it without arguments to get help:

    ./g8r

Or to get help about a specific topic:

    ./g8r help add-host

(FIXME: Much of the help is not yet written.)j


### Adding and provisioning a host

To add a host (a static Caddy webserver) to your default domain:

    # add-host <type> <hostname>
    ./g8r add-host web www

If the server already exists and you know its public IP addresses,
this form is preferred:

    IPV4=1.2.3.4 IPV6=2001:DB8::1 ./g8r add-host web www

This creates the host definition,
and assigns it a secret which is used to bootstrap and download updates.
The tool will print out the server secret and a bootstrapping URL.

If the VPS already exists,
you can provision it manually by logging on to your VPS and running as root:

    curl https://bootstrapping/url/here/... |bash

Or if you have configured and enabled the [Linode integration](docs/LINODE.md),
you can create the VPS and bootstrap it like so:

    ./tree/linode/deploy.sh web-www-SECRET

Once you have created and provisioned the server,
you may want to update /etc/hosts on your Governator Server:

    ./g8r etc-hosts

(Actually updating public DNS is a TODO/FIXME item.)


### Adding another entire domain




## But Why?

My lofty goal is to minimize the complexity of the special purpose tools used to administer servers,
and rely on battle tested,
stable and *unlikely to change* tools and standards as much as possible.

Aside from these *standard tools*,
all of the code used to manage Governated servers fits comfortably in this repository.
It's not a lot of code,
it can be read and understood - and customized.

Reducing dependencies and keeping the system as minimalist as possible,
should reduce the time spent on maintaining and updating the administration tools themselves.
This goal is stability for years,
decades even.
Updating servers is necessary.
I would rather not have to also worry about updating the tool I use to update the servers.

Also,
I'm a bit of a troll.
I can't wait to tell everyone I manage my infra using curl|bash.


## Credits and Thanks

Governator is (C) 2026,
Bjarni R. Einarsson <https://bre.klaki.net/> and
The Beanstalks Project ehf <https://pagekite.net/company/>.

The license for this collection of tools and code is MIT.
See [LICENSE.txt](LICENSE.txt) for details.

Many thanks to Kría for the cool gator.

