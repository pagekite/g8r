#!/usr/bin/python3
"""
This is a command-line utility that allows one to use the Jinja2 templating
engine to work with static files.

Usage examples:

    # Set the document root
    export JINJATOOL_ROOT=/path/to/documents

    # Decide which variables to load and their ordering
    export JINJATOOL_VARS=jinjatool.vars:jinjatool.json

    # Render to standard output
    jinjatool.py input.jinja

    # Render to a named file
    jinjatool.py input.jinja:output.html

    # Render the same template twice using different variables
    jinjatool.py title=Great input.jinja:great.html \\
                 title=Sucks input.jinja:sucks.html

    # Calculate Makefile-style dependencies for some templates
    jinjatool.py --deps thing.jinja otherthing.jinja

The variables provided to the Jinja rendering engine are the Unix
environment variables, optionally updated/augmented the contents of
variable definition files found in the filesystem (per JINJATOOL_VARS)
or with foo=bar pairs from the command line.

Variable definitions and input/output rendering pairs can be mixed and
matched and will be processed in order.
"""
import copy
import datetime
import hashlib
import jinja2
import jinja2.utils
import json
import os
import re
import subprocess
import sys
import time

from jinja2.ext import Extension
from markdown import markdown

try:
    from markupsafe import Markup
except ImportError:
    from jinja2 import Markup

try:
    from jinja2 import pass_context
except ImportError:
    from jinja2 import contextfunction as pass_context


# Default list of files to load (in order) for variables
JINJATOOL_DEFAULT_VARS = 'jinjatool.vars:jinjatool.json'

# Used to auto-add <a name=...> to headings.
HEADINGS_RE = re.compile(r'(<[Hh]\d+[^>]*>)([^>]*)(</[Hh]\d+>)', flags=re.S)
AUTO_TOC_RE = re.compile(r'<!-- TOC: ((?:[Hh]\d+\s*)*) *-->', flags=re.S)

# This lets us spy on which files get opened, for calculating dependencies.
REAL_OPEN = open
OPENED_FILES = set()

def open(fn, *args, **kwargs):
    global OPENED_FILES
    try:
        rv = REAL_OPEN(fn, *args, **kwargs)
        OPENED_FILES.add(os.path.abspath(fn))
        return rv
    except:
#       sys.stderr.write('Failed to open: %s\n' % fn)
        raise

jinja2.open = open
jinja2.utils.open = open


def toc_friendly_markdown(text):
    counter = 0
    sections = []
    def add_anchors(m):
        nonlocal counter, sections
        h, title, he = m.group(1), m.group(2), m.group(3)
        counter += 1
        aname = 'h%d' % counter
        if '#=' in title:
            title, aname = title.rsplit('#=', 1)
        title = title.strip()
        if aname in ('#', ''):
            return '%s%s%s' % (h, title, he)
        else:
            sections.append((aname, h[1:3].lower(), title))
            return ('<a class="anchor" name="%s"></a>%s%s%s'
                % (aname, h, title, he))

    def gen_auto_toc(m):
        headings = m.group(1).lower().split()
        lines = ['<div class="jinjatool_toc"><ul>']
        toc = []
        for aname, hN, title in sections:
            if hN in headings:
                toc.append((headings.index(hN), aname, title))
        toc_depth = 0
        for depth, aname, title in toc:
            while depth > toc_depth:
                lines.append('%s <ul>' % (' ' * toc_depth))
                toc_depth += 1
            while depth < toc_depth:
                toc_depth -= 1
                lines.append('%s </ul>' % (' ' * toc_depth))
            lines.append(
                '%s <li><a href="#%s">%s</a>'
                % (' ' * toc_depth, aname, title))
        while (toc_depth+1):
            lines.append('%s</ul>' % (' ' * toc_depth))
            toc_depth -= 1
        return '\n' + '\n'.join(lines) + '</div>\n'

    mtext = HEADINGS_RE.sub(add_anchors, markdown(text))
    mtext = AUTO_TOC_RE.sub(gen_auto_toc, mtext)

    return mtext


@pass_context
def get_all_vars(context, prefixes=None):
    """Returns a dictionary of all variables currently in scope"""
    def _check(k):
        if not prefixes:
            return True
        for p in prefixes:
            if k.startswith(p):
                return True
        return False
    return dict((k, v) for k, v in context.get_all().items() if _check(k))


# A Jinja extension which gives us shell commands, markdown and json processing
class JinjaToolExtension(Extension):
    def __init__(self, env):
        Extension.__init__(self, env)
        env.globals['bash'] = self._bash
        env.globals['cat'] = self._cat
        env.globals['ls'] = self._ls
        env.globals['all_vars'] = get_all_vars
        env.filters['bash'] = self._bash
        env.filters['max'] = self._max
        env.filters['min'] = self._min
        env.filters['hash'] = self._hash
        env.filters['date'] = self._date
        env.filters['cal'] = self._cal
        env.filters['schedule'] = self._schedule
        env.filters['health'] = self._health
        env.filters['set'] = self._set
        env.filters['without'] = self._without
        env.filters['markdown'] = self._markdown
        env.filters['to_json'] = self._to_json
        env.filters['from_json'] = self._from_json
        env.filters['from_rfc822'] = self._from_rfc822
        env.filters['from_vars_txt'] = self._from_vars_txt
        env.filters['from_metrics'] = self._from_metrics
        env.filters['friendly_bytes'] = self._friendly_bytes

    def _bash(self, data=None, command=None):
        if (data is not None) and (command is None):
            command, data = data, None
        try:
            so, se = subprocess.Popen(['bash', '-c', command],
                    stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE
                ).communicate(input=bytes(data or '', 'utf-8'))
            return str(so or se or b'FAILED', 'utf-8').strip()
        except (OSError, IOError):
            return None

    def _cat(self, fn, real_root=False):
        try:
            if fn.startswith('/') and not real_root:
                fn = os.path.join(self.environment.jinjatool_root, fn[1:])
            return str(open(os.path.expanduser(fn), 'rb').read(), 'utf-8')
        except (OSError, IOError):
            return None

    def _ls(self, dirname, pattern='^[^\.]'):
        try:
            OPENED_FILES.add(os.path.abspath(dirname))
            return sorted([fn for fn in os.listdir(dirname)
                           if re.search(pattern, fn)])
        except (OSError, IOError):
            return None

    def _max(self, data):
        return max(data or [0])

    def _min(self, data):
        return min(data or [0])

    def _friendly_bytes(self, data):
        b = int(data or 0)
        for base, suffix in (
                (2**30, 'gb'),
                (2**20, 'mb'),
                (2**10, 'kb')):
            if b > base:
                return '%2.1f%s' % (b / base, suffix)
        return '%d bytes' % (b,)

    def _hash(self, data, algo='sha1'):
        _b = lambda t: bytes(t, 'utf-8') if isinstance(t, str) else t
        return {
                'md5': hashlib.md5,
                'sha1': hashlib.sha1,
                'sha256': hashlib.sha256,
                'sha512': hashlib.sha256
            }[algo.lower()](_b(data)).hexdigest()

    def _date(self, data, fmt='%Y-%m-%d', field='date', tz=None):
        if isinstance(data, dict):
            d = copy.copy(data)
            d[field] = self._date(d[field], fmt=fmt)
            return d
        elif isinstance(data, int) or isinstance(data, float):
            data = '@%d' % data
        try:
            if fmt[:1] not in ('-', '+'):
                fmt = '+%s' % fmt
            data = data.replace(',', ' ')
            if ':' not in data and data != 'now' and '@' not in data:
                data += ' 12:00'
            return str(subprocess.check_output(['date', fmt, '--date', data],
                                               env={'TZ': tz} if tz else None,
                                               ), 'utf-8').strip()
        except (OSError, IOError, subprocess.CalledProcessError):
            return data

    def _cal(self, date_map):
        def _dt(key):
            return datetime.datetime(*(int(k) for k in key.split('-')))

        details = {}
        first = None
        for key in sorted(list(date_map.keys())):
            dt = _dt(key)
            if first is None:
                first = dt
            details[dt] = date_map[key]
        if first is None:
            first = datetime.datetime.now()

        cur = first
        mon = first.month
        cal = [cur.strftime('%B\n')]
        one = datetime.timedelta(days=1)
        while cur.day > 1:
            cur -= one
        while cur.isoweekday() > 1:
            cur -= one
        while True:
            cal.append('%2s' % (cur.day if cur.month >= mon else ' '))
            if cur in details:
                cal[-1] = '<b class="ev" title="%s">%s</b>' % (details[cur], cal[-1])
                del details[cur]
            if cur.isoweekday() == 7:
                cal.append('\n')
            cur += one
            if cur.month != mon and cur >= first:
                if not details:
                    break
                mon = cur.month
                cal.append(cur.strftime('\n\n%B\n'))
                cal.extend(['  '] * (cur.isoweekday()-1))

        return (' '.join(cal)).replace(' \n', '\n')

    def _health(self, metrics):
        summary = {
            'healthy': True,
            'failing': [],
            'services': []}
        for k, v in metrics.items():
             if k.endswith('_healthy_seconds'):
                 parts = k.split('_')
                 service = '_'.join(parts[1:-2])
                 summary['services'].append(service)
                 if v < 0:
                     summary['healthy'] = False      
                     summary['failing'].append(service)
        if len(summary['failing']):
            summary['summary'] = 'Unhealthy, failing: ' + ', '.join(summary['failing'])
        else:
            summary['summary'] = 'Healthy! OK: ' + ', '.join(summary['services'])
        return summary
   
    def _schedule(self, schedule, days=35, month=True, week=False):
        one = datetime.timedelta(days=1)
        cur = datetime.datetime.now()
        if week:
            while cur.weekday() > 0:
                cur -= one
        elif month:
            while cur.day > 1:
                cur -= one

        expanded = {}
        for i in range(days):
            day = cur.strftime('d%d')
            wday = cur.strftime('w%w')
            week = cur.strftime('W%Ww%w')
            for s in schedule:
                if s.startswith(day) or s.startswith(wday) or s.startswith(week):
                    event = '%s: %s' % (s[-3:], schedule[s][1])
                    expanded[cur.strftime('%Y-%m-%d')] = event
            cur += one
            if month and cur.day == 1:
                break

        return expanded

    def _set(self, data, field, var):
        d = copy.copy(data)
        d[field] = var
        return d

    def _without(self, data, skip=[]):
        d = {}
        skip = set([s.lower() for s in skip])
        for k, v in data.items():
            if k.lower() not in skip:
                d[k] = v
        return d

    def _markdown(self, text):
        return Markup(toc_friendly_markdown(mtext))

    def _to_json(self, data):
        j = json.dumps(data, sort_keys=True, indent=2)
        j = j.replace('<', '\\x3c').replace('&', '\\x26')
        return Markup(j)

    def _from_json(self, data):
        if data:
            return json.loads(data)
        else:
            return {}

    def _from_rfc822(self, text, parse_markdown=True):
        header, body = ((text or '') + '\n\n'
                        ).replace('\r', '').split('\n\n', 1)
        header_lines = header.splitlines()
        if not (header_lines and ':' in header_lines[0]):
            body = header + '\n\n' + body
            header, header_lines = '', []

        rfc822 = dict([(h1.lower(), h2.strip())
                       for h1, h2 in [h.split(':', 1)
                                      for h in header_lines if ':' in h]])

        if parse_markdown and rfc822.get('format') in (None, '', 'markdown'):
            rfc822['body'] = toc_friendly_markdown(body).rstrip()
        else:
            rfc822['body'] = body.rstrip()
        return rfc822

    def _from_vars_txt(self, data):
        vdict = {}
        for line in (data or '').splitlines():
            line = line.split('#')[0].strip()
            if '=' not in line:
                continue
            var, val = line.split('=', 1)
            vdict[var.strip()] = val.strip().strip("\"'")
        return vdict

    def _from_metrics(self, data):
        vdict = {}
        if data:
            for line in data.splitlines():
                if not line.strip():
                    continue
                var, val = [v.strip() for v in line.split('=', 1)]
                val = val.strip("\"'")
                try:
                    if ' ' in val:
                        val = [int(v) for v in val.split()]
                    elif '.' in val:
                        val = float(val)
                    else:
                        val = int(val)
                except ValueError:
                    pass
                vdict[var] = val
        return vdict


def MakeJinjaEnvironment(jinjatool_root):
    script_path = os.path.dirname(os.path.abspath(__file__))
    script_parent = os.path.abspath(os.path.join(script_path, '..'))
    searchpath = [script_path, script_parent, '/', '.']
    if jinjatool_root:
        searchpath[:0] = [jinjatool_root]
    env = jinja2.Environment(
        loader=jinja2.FileSystemLoader(searchpath=searchpath),
        autoescape=True,
        extensions=['jinja2.ext.with_',
                    'jinja2.ext.do',
                    'jinja2.ext.autoescape',
                    JinjaToolExtension])
    env.jinjatool_root = jinjatool_root
    return env


def Main():
    global OPENED_FILES

    if '--help' in sys.argv or len(sys.argv) == 1:
        print(__doc__)
        return

    jinjatool_root = os.getenv('JINJATOOL_ROOT')
    jinja_env = MakeJinjaEnvironment(jinjatool_root)
    variables = {}
    variables.update(os.environ)
    variables.update({
        'now': int(time.time())})
    depcheck = False
    basedir = os.path.abspath('.')

    def load_vars_from_file(vfdir):
        jt_vars = variables.get('JINJATOOL_VARS', JINJATOOL_DEFAULT_VARS)
        for vfn in (os.path.join(vfdir, v) for v in jt_vars.split(':')):
            if not os.path.exists(vfn):
                continue
            with open(vfn, 'r') as vf:
                if vfn.endswith('.yml'):
                    import yaml
                    variables.update(yaml.safe_load(vf))
                elif vfn.endswith('.json'):
                    variables.update(json.load(vf))
                else:
                    for line in vf:
                        line = line.split('#')[0]
                        if '=' in line:
                            k, v = line.split('=', 1)
                            variables[k.strip()] = v.strip().strip("\"'")

    for arg in sys.argv[1:]:

        if '=' in arg:
            k, v = arg.split('=', 1)
            variables[k] = v

        elif arg.startswith('-'):
            arg = arg.lstrip('-')
            if arg == 'deps':
                depcheck = True
            elif arg == 'nodeps':
                depcheck = False
            elif arg.startswith('vars='):
                load_vars_from_file(os.path.abspath(arg[5:]))

        else:
            infile, ofile = (':' in arg and arg.split(':') or (arg, None))
            inpath = os.path.abspath(infile)
            inrelpath = os.path.relpath(inpath)
            if not os.path.exists(inpath):
                raise ValueError("Missing file: %s" % inpath)

            # Check for jinjatool.vars files, with output-specific variables
            opathvars = os.path.dirname(os.path.abspath(ofile or infile))
            if jinjatool_root and opathvars.startswith(jinjatool_root + '/'):
                parent = jinjatool_root
                parts = opathvars[len(jinjatool_root):].split('/')
                for p in parts:
                    parent = os.path.join(parent, p)
                    load_vars_from_file(parent)
            else:
                load_vars_from_file(opathvars)

            # This renders the data, hooray!
            try:
                os.chdir(variables.get('dir', os.path.dirname(inpath)))
                template = jinja_env.get_template(inpath)
                data = bytes(template.render(variables), 'utf-8')
                os.chdir(basedir)
            except:
                if depcheck:
                    print('# FAILED DEPS: %s' % inpath)
                    continue
                else:
                    raise

            if depcheck:
                deps = sorted([os.path.relpath(o) for o in OPENED_FILES])
                if ofile:
                    relofile = os.path.relpath(os.path.abspath(ofile))
                    if relofile in deps:
                        deps.remove(relofile)
                    print('%s: %s' % (relofile, ' '.join(
                        os.path.relpath(os.path.abspath(os.path.realpath(d)))
                        for d in deps)))
                else:
                    deps.remove(inrelpath)
                    print('%s: %s'  % (inrelpath, ' '.join(
                        os.path.relpath(os.path.abspath(os.path.realpath(d)))
                        for d in deps)))

                # Clear caches so each dependency list is correct
                jinja_env = MakeJinjaEnvironment(jinjatool_root)
                OPENED_FILES = set()
            else:
                if ofile:
                    open(ofile, 'wb').write(data)
                else:
                    sys.stdout.buffer.write(data)
                    if b'<html' in data[:80]:
                        sys.stdout.write('\n<!-- EOF:%s -->\n' % infile)

if __name__ == '__main__':
    Main()
