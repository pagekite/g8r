# Canary Hosts

This folder is for CI/CD and staged rollouts.

Add symbolic links from here to which-ever servers you would like to treat as canaries.

The migration rules in [../automations.json](../automations.json)
can treat these servers as candidates for immediate updates when new software versions are available,
and can gate deploying software to other servers upon the canaries passing health checks.

**Note:** Work in progress! This doesn't work just yet.
