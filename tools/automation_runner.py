#!/usr/bin/env python3
#
# This process runs in a loop, running some or all of the automations
# defined in `automations.json`.
#
# The order of processing is always the same (as defined by the JSON file),
# and there is never more than one automation in flight at the same time.
#
# Which automations are scheduled to run depends on what has been seen
# recently in the watched log files, or in the cron section of the JSON.
#
# Automations can be chained, one can trigger another by printing to
# STDOUT a line formatted as so: "AUTOMATION: NAME", where NAME is the
# name of the automation to trigger. That this will only work if the
# triggered automation is scheduled to run after the one triggering it.
#

import datetime
import json
import os
import re
import sys
import shutil
import subprocess
import time


DEFAULT_CONFIG_FILES = ('automations.json', 'automations-local.json')
DEFAULT_G8R_HOME = os.path.normpath(os.path.join(os.path.dirname(__file__), '..'))

COMMON_WEBLOG_RE = re.compile(
  r'(?P<log_ip>[0-9a-fA-F\:\.]+) '
  r'(?P<log_host>[0-9a-zA-Z\._-]+) '
  r'(?P<log_user>[0-9a-zA-Z\._-]*) '
  r'\[(?P<log_time>[0-9a-zA-Z:\s/+_-]+)\] '
  r'"(?P<log_request>[^"]*?)" '
  r'(?P<log_status>\d{3}) '
  r'(?P<log_size>\S+) '
  r'"(?P<log_referer>.*?)" '
  r'"(?P<log_agent>.*?)"')


class AutomationRunner:
    def __init__(self, path_to_configs=None):
        if not path_to_configs:
            path_to_configs = DEFAULT_CONFIG_FILES

        g8r_home = os.getenv('G8R_HOME') or DEFAULT_G8R_HOME
        self.path_to_configs = []
        for ptc in path_to_configs:
            if not ptc.startswith('/'):
                ptc = os.path.join(g8r_home, 'tree', ptc)
            self.path_to_configs.append(ptc)

        self.sleep_seconds = 10
        self.log_files = []
        self.log_positions = {}
        self.log_events = []
        self.schedule = []
        self.sched_last_ran = int(time.time()) - 30
        self.automations = []
        self.ran_recently = {}
        self.config = {}
        self.keep_running = True

    def my_time(self, ts):
         return datetime.datetime.fromtimestamp(ts).strftime("%A %B %Y-%m-%d %Hh%Mm%Ss")

    def stdout(self, something):
        print(something)

    def stderr(self, something):
        sys.stderr.write('[%s] %s\n'
            % (self.my_time(time.time()), something.rstrip()))

    def load_config(self):
        config = {}
        try:
            for path in self.path_to_configs:
                if os.path.exists(path):
                    with open(path, 'r') as fd:
                        cfg = json.loads(fd.read())
                    if not config:
                        config = cfg
                        continue
                    for k, v in cfg.items():
                        if k not in config:
                            config[k] = v
                        elif isinstance(v, list):
                            config[k].extend(v)
                        elif isinstance(v, dict):
                            config[k].update(v)
                        else:
                            config[k] = v
        except Exception as e:
            self.stderr('FAILED TO LOAD CONFIG: %s' % e)
        if not config:
            return False

        self.config = config
        self.sleep_seconds = self.config.get('sleep_seconds', self.sleep_seconds)
        self.log_files = self.config['log_files']
        self.log_events = self.config['log_events']
        self.automations = self.config['automations']

        self.schedule = []
        for pattern, event in self.config.get('scheduled_events', {}).items():
            if pattern.startswith('#'):
                continue
            pattern = pattern.replace(' ', r'\b.*\b')
            self.schedule.append((re.compile(pattern), event))

        for event in self.log_events:
            event[0] = re.compile(event[0])

        for lf in self.log_files:
            if lf not in self.log_positions:
                self.log_positions[lf] = -1

        for lf in list(self.log_positions.keys()):
            if lf not in self.log_files:
                del self.log_positions[lf]

        return True

    def parse_log_match(self, line, matches):
        info = {}
        if line and line[0] == '{':
            info.update(json.loads(line))
        else:
            logparse = COMMON_WEBLOG_RE.search(line)
            if logparse:
                info.update(logparse.groupdict())
        info.update(matches.groupdict())
        return info

    def check_stream(self, fd):
        for line in fd:
            line = line.rstrip()
            for event in self.log_events:
                matches = event[0].search(line)
                if matches:
                    yield (event[1:], self.parse_log_match(line, matches))

    def check_file(self, fn):
        with open(fn, 'r') as fd:
            pos = self.log_positions[fn]
            if pos >= 0:
                if pos <= os.path.getsize(fn):
                    fd.seek(pos, 0)

            yielded = 0
            for event_tuple in self.check_stream(fd):
                yielded += 1
                yield event_tuple

            self.log_positions[fn] = fd.tell()
            if yielded:
                self.stdout('Processed: %s[%d:]' % (fn, pos))

    def check_all_logs(self):
        for lf in self.log_files:
            if os.path.exists(lf):
                for event_tuple in self.check_file(lf):
                    yield event_tuple

    def run_cmd(self, cmd):
        try:
            child = subprocess.Popen(cmd,
                stderr=subprocess.PIPE,
                stdout=subprocess.PIPE,
                encoding='utf-8',
                text=True)

            (stdout, stderr) = child.communicate()
            sys.stderr.write(stderr)

            exitcode = child.wait()
            if exitcode != 0:
                sys.stderr.write('%s failed with code: %d\n' % (cmd[0], exitcode))
                return

            for line in stdout.splitlines():
                line = line.rstrip()
                if line.startswith('AUTOMATION:'):
                    yield line
                else:
                    self.stdout(line)

        except KeyboardInterrupt:
            child.kill()

    def run_command(self, event, cmd, args, info):
        cmd_path = shutil.which(cmd) or cmd
        cmd_list = [cmd_path]
        cmd_string = None
        try:
            for a in args:
                if a and a[0] == '$':
                    cmd_list.append(str(info[a[1:]]))
                else:
                    cmd_list.append(a)

            cmd_string = ' '.join([cmd] + cmd_list[1:])
            if cmd_string in self.ran_recently:
                return

            self.ran_recently[cmd_string] = True
            if not os.path.exists(cmd_path):
                raise OSError('Not found: %s' % cmd)

            self.stdout(' * %s: %s' % (event, cmd_string))
            yield [a.split(': ')[1] for a in self.run_cmd(cmd_list)], {}

        except Exception as e:
            if not cmd_string:
                cmd_string = '%s%s%s' % (cmd, args, info)
            self.stderr("%s FAILED: %s\n!! %s: %s"
                % (event, cmd_string, type(e).__name__, e))

    def check_schedule(self):
        now = int(time.time())
        while self.sched_last_ran < now:
            self.sched_last_ran += 60
            time_string = self.my_time(self.sched_last_ran)
            events = set()
            for re, event in self.schedule:
                if re.search(time_string):
                    events.add(event)
            yield list(events), {'ts': self.sched_last_ran}

    def loop(self):
        start_time = time.time()
        deadline = None
        while self.keep_running:
            deadline = self.loop_main(start_time, deadline)
            if deadline is False:
                break
            time.sleep(self.sleep_seconds)

    def loop_main(self, start_time, deadline):
        self.load_config()
        self.ran_recently = {}

        now = time.time()
        max_run_hours = self.config.get('max_run_hours')
        if max_run_hours:
            deadline = start_time + (max_run_hours * 3600)
            if now >= deadline:
                self.stdout('====== Done, good-bye! ======')
                return False

            ttl = int(deadline - now)
            self.stdout('====== %s (ttl=%ds) ======' % (self.my_time(now), ttl))
        else:
            deadline = None
            self.stdout('====== %s ======' % (self.my_time(now),))

        events_seen = {}
        def _process_events(_stream):
            for events, info in _stream:
                for ev in events:
                    es = events_seen[ev] = events_seen.get(ev, [])
                    es.append(info)

        _process_events(self.check_all_logs())
        _process_events(self.check_schedule())

        for automation in self.automations:
            event, cmd, args = automation[0], automation[1], automation[2:]
            if event in events_seen:
                if args:
                    for info in events_seen[event]:
                        _process_events(self.run_command(event, cmd, args, info))
                else:
                    _process_events(self.run_command(event, cmd, args, {}))

        return deadline


if __name__ == '__main__':
    try:
        ar = AutomationRunner(sys.argv[1:])
        ar.loop()
    except KeyboardInterrupt:
        pass
