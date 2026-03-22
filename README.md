# Governator - g8r

Bash your servers into submission!


## Just Keep Bootstrapping

<img src="imgs/Governator-by-Kria.png" alt="" width="35%" align=right>

This is (or will be) a framework and collection of minimalist tools which make it easy to provision and manage a modest fleet of (VPS) servers.
Rather than create a whole suite of tools to describe,
implement and deploy server configurations,
g8r uses shell scripts and the web.

The code which provisions or updates any given server is a collection of small shell scripts.
These scripts are generated and organized using the exact same techniques as a static website generator:
a tree of content,
combining templates and variables to generate bash scripts
(instead of HTML).

And similarly,
rather than pushing instructions to the targets,
servers download their management scripts,
custom binaries (including docker images) and auxillary data from a static HTTP server.
Using curl or wget.
Whether new updates need to be downloaded and applied (or not) is communicated using HTTP's existing vocabulary for checking for updates to static content.

There are a few keys to making this work:

   1. Security: URLs must be unguessable, unshared and served over HTTPS
   2. A lot of symbolic links
   3. Shell scripts install shell scripts to help run shell scripts
   4. Updates are scheduled by:
      * cron
      * a custom tool reacting to something exciting in a log file
      * an impatient human

The goal of this repo is to help get you started with some working examples,
and document what rules to follow when you make your own updates.


## But Why?

My lofty goal is to minimize the complexity of the special purpose tools used to administer servers,
and rely on battle tested,
stable and *unlikely to change* tools and standards as much as possible.

Updating servers is necessary.
I would rather not have to also worry about updating the tool I use to update the servers.

Also,
Ansible kept yelling at me that my rules were deprecated.
So I'm deprecating Ansible.
