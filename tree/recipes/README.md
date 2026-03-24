# Recipes

Recipes should end in .jinja-sh if you want templating magic,
but you can of course drop in "static" files as well.

Recipes starting with 0 are auto-run as part of the default boostrapping and updating process.
They run in lexicographical order.

Any other recipes are run when you decide to run them
(e.g. as part of a cron job).
