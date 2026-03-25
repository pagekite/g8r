#!/usr/bin/env python3
#
# This process runs on demand, updating variable definitions in JSON files
# found under `tree/`, depending on rules defined in `tree/automations.json`.
#
# When an update rule is applied, variables (values) are first gathered from
# one or more JSON files (using shell globbing rules to select input files),
# renamed as necessary and then written to another set of JSON files (again,
# globbing).
#
# Use cases:
#   - Pick up new version numbers from a manifest and update canary configs
#   - Pick up stable version numbers from canary configs and apply globally
#   - Gather per-host IP addresses and generate a unified inventory
#
# This script is invoked as necessary by `automation-runner.py`. Depending
# on the configuration (and whether anything changed), it may emit events
# which then trigger further processing.
#
# TODO:
#   - Implement preconditions (needed for canary->stable versioning)
#   - Implement sanity checks so we don't blow away something important
#   - Allow mapping rules to define paths to nested variables, not just
#     the top level
#

import datetime
import glob
import json
import os
import time


DEFAULT_CONFIG_FILE = 'automations.json'
DEFAULT_G8R_HOME = os.path.normpath(os.path.join(os.path.dirname(__file__), '..'))


class VaryVariables:
    def __init__(self, path_to_config):
        if not path_to_config:
            g8r_home = os.getenv('G8R_HOME') or DEFAULT_G8R_HOME
            path_to_config = os.path.join(g8r_home, 'tree', DEFAULT_CONFIG_FILE)
        self.path_to_config = path_to_config

        self.config = {}
        self.rules = []
        self.load_config()
        os.chdir(os.path.join(os.path.dirname(__file__), '..'))

    def my_time(self, ts):
         return datetime.datetime.fromtimestamp(ts).strftime("%A %B %Y-%m-%d %Hh%Mm%Ss")

    def stdout(self, something):
        print(something)

    def stderr(self, something):
        sys.stderr.write('[%s] %s\n'
            % (self.my_time(time.time()), something.rstrip()))

    def load_config(self):
        try:
            with open(self.path_to_config, 'r') as fd:
                self.config = json.loads(fd.read())
        except Exception as e:
            self.stderr('FAILED TO LOAD CONFIG: %s' % e)
            return

        self.rules = self.config.get('update_variables', [])

    def check_preconditions(self, rule):
        return True  # FIXME

    def glob_filenames(self, filespecs, group=None):
        for filespec in sorted(filespecs):
            if group:
                filespec = filespec.replace('$GROUP', group)
            for fn in sorted(glob.glob(filespec)):
                yield fn

    def groups(self, rule):
        yielded = 0
        if rule.get('group_by'):
            for fn in self.glob_filenames(rule['group_by']):
                yielded += 1
                yield fn
        if not yielded:
            yield None

    def gather(self, rule, group):
        found = {}
        def _merge(dst, src, k):
            if isinstance(src[k], dict) and k in dst:
                for k2 in src[k]:
                    _merge(dst[k], src[k], k2)
            else:
                dst[k] = src[k]
        for fn in self.glob_filenames(rule['read'], group):
            try:
                with open(fn, 'r') as fd:
                    data = json.loads(fd.read())
                    for vn in rule['map']:
                        if vn in data:
                            _merge(found, data, vn)
                        self.stdout('In %s: %s=%s' % (fn, vn, data[vn]))
            except Exception as e:
                self.stderr('%s: When reading %s: %s' % (type(e).__name__, fn, e))
        return found

    def update(self, rule, group, inputs):
        changed = []
        for fn in self.glob_filenames(rule['write'], group):
            try:
                with open(fn, 'r') as fd:
                    data = json.loads(fd.read())
                changing = False
                for iv, ov in sorted(list(rule['map'].items())):
                    if iv not in inputs:
                        continue
                    if data.get(ov) != inputs[iv]:
                        data[ov] = inputs[iv]
                        changing = True
                if changing:
                    with open(fn, 'w') as fd:
                        fd.write(json.dumps(data, indent=2))
                        self.stdout('Updated: %s' % fn)
                    changed.append(fn)
            except Exception as e:
                self.stderr('%s: When updating %s: %s' % (type(e).__name__, fn, e))
        return changed

    def vary(self):
        for rule in self.rules:
            self.stdout('Checking rule: %s' % (rule['map']))
            if self.check_preconditions(rule):
                for group in self.groups(rule):
                    if self.update(rule, group, self.gather(rule, group)):
                        for auto_event in rule['emit_events']:
                            self.stdout('AUTOMATION: %s' % auto_event)


if __name__ == '__main__':
    import sys
    VaryVariables(sys.argv[1] if (len(sys.argv) > 1) else None).vary()
