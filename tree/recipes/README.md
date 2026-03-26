# Script Recipes

These are the shared recipes for installing components of a running server.
You can and should modify these or add your own!

The default set is:

    000_bootstrap.jinja-sh     - Initial bootstrapping, common g8r dependencies

    101_etc-hosts.jinja-sh     - Updates /etc/hosts with info from our inventory
    130_install-caddy.jinja-sh - Install Caddy, configured for static websites

    900_hourly-cron.jinja-sh   - A template of an hourly cron job
    900_update.jinja-sh        - Fetches updated g8r scripts and runs them

Script recipes should end in `.jinja-sh`.
You can add other files,
but beware that `make clean` will nuke anything ending in `.sh`.

A selection of these templates gets symlinked into the configuration folder for each server.
Recipes starting with the number `1` are auto-run as part of the default boostrapping and updating process.
They run in lexicographical order.

Any other recipes are run when you decide to run them
(e.g. by hand, or as part of a cron job).
