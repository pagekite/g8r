# Governator - g8r

curl|bash your servers into shape!


## What's this?

<img src="docs/imgs/Governator-by-Kria.png" alt="" width="35%" align=right>

This is (or will be) a framework and collection of minimalist tools which make it easy to provision and manage a modest fleet of (VPS) servers.

Governator sits somewhere between configuration managment (like Ansible)
and orchestration (like Kubernetes).
Like Ansible (or Puppet, or Chef),
Governator describes how to configure and/or update a fleet of servers.
Dabbling in orchestration,
g8r also has opinions on how to implement CI/CD workflows,
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
you will provide your `kitename.pagekite.me` domain name as the answer to question 3 above.
Note that managed servers will only be able to update themselves when the Governator Server is online.


## But Why?

My lofty goal is to minimize the complexity of the special purpose tools used to administer servers,
and rely on battle tested,
stable and *unlikely to change* tools and standards as much as possible.

Updating servers is necessary.
I would rather not have to also worry about updating the tool I use to update the servers.

Also,
Ansible kept yelling at me that my rules were deprecated.
So I'm deprecating Ansible.
