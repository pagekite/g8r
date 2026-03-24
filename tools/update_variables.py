#!/usr/bin/env python3
#
# This process runs on demand, updating variable definitions in JSON files
# found under `config/`, depending on rules defined in `automations.json`.
#
# This script is invoked as necessary by `automation-runner.py`. Depending
# on the configuration (and whether anything changed), it may emit events
# which then trigger further processing.
#

import datetime
import glob
import json
import os


DEFAULT_CONFIG_FILE = 'automations.json'
DEFAULT_G8R_HOME = os.path.normpath(os.path.join(os.path.dirname(__file__), '..', 'tree'))


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

    def glob_filenames(self, filespecs):
        for filespec in filespecs:
            for fn in glob.glob(filespec):
                yield fn

    def gather(self, rule):
        found = {}
        def _merge(dst, src, k):
            if isinstance(src[k], dict) and k in dst:
                for k2 in src[k]:
                    _merge(dst[k], src[k], k2)
            else:
                dst[k] = src[k]
        for fn in self.glob_filenames(rule['read']):
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

    def update(self, rule, inputs):
        changed = []
        for fn in self.glob_filenames(rule['write']):
            try:
                with open(fn, 'r') as fd:
                    data = json.loads(fd.read())
                changing = False
                for iv, ov in rule['map'].items():
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
                if self.update(rule, self.gather(rule)):
                    for auto_event in rule['emit_events']:
                        self.stdout('AUTOMATION: %s' % auto_event)


if __name__ == '__main__':
    import sys
    VaryVariables(sys.argv[1] if (len(sys.argv) > 1) else None).vary()
