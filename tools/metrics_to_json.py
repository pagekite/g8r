#!/usr/bin/env python3
"""
Usage: metrics_to_json.py [-|url|fqdn] [--oneline|--help] [filter terms ...]

Examples:
    $ metrics_to_json.py http://host/metrics g8r >host.g8r.json
    $ metrics_to_json.py - vmstat netstat <metrics.om |jq

If there are no arguments, or '-' is one of the arguments, this script
will function as a filter which converts OpenMetrics on standard input
into JSON on standard output.

Otherwise the first argument is treated as an URL or DNS hostnme to
download OpenMetrics from, which is then output as JSON.

Any other arguments enable filtering of the output; the arguments are
treated as keywords which must be found using a simple substring search
in a metric's name, in order for it to be included in the output.
"""
import base64
import urllib.request
import json
import os
import re
import time


INDENT = int(os.getenv('JSON_INDENT', 2))
WANTED_TYPES = ['counter', 'gauge']
METRIC_RE = re.compile(r'^([a-zA-Z_]\S+)\s+([\d\.eE\+-]+)')
HEALTHY_TTL = float(os.getenv('HEALTHY_TTL', 900))


def calculate_synthetic_metrics(metrics):
    # Caculates some useful synthetic metrics.
    # This is primarily to do with estimating service health.
    now = time.time()
    for metric in list(metrics.keys()):
        if not metric.startswith('g8r_'):
            continue
        if metric.endswith('_healthy'):
            m_health0 = metric.replace('_healthy', '_health0')
            m_healthy_secs = metric + '_seconds'
            if m_health0 in metrics and m_healthy_secs not in metrics:
                if metrics[metric] < now - HEALTHY_TTL:
                    # The healthy metric is obsolete, assume we are actually
                    # not healthy at all.
                    metrics[m_healthy_secs] =  metrics[metric] - now

                elif metrics[metric] < metrics[m_health0]:
                    # This means we know we are unhealthy, we can use wall-clock
                    # time to calculte for how long.
                    metrics[m_healthy_secs] = metrics[metric] - now

                else:
                    # For positive health times, use whatever was updated last.
                    metrics[m_healthy_secs] = metrics[metric] - metrics[m_health0]


def get_username_and_password(url):
    parts = url.split('/')
    if not (':' in parts[2] and '@' in parts[2]):
        return url, None, None
    userpass, parts[2] = parts[2].split('@', 1)
    u, p = userpass.split(':')
    return '/'.join(parts), u, p


def fetch_openmetrics_as_json(url, filters, wrap=None, username=None, password=None):
    try:
        headers = {}
        if not username:
            url, username, password = get_username_and_password(url)
        if username:
            headers['Authorization'] = 'Basic %s' % str(base64.b64encode(
                bytes('%s:%s' % (username, password or username), 'utf-8')),
                'utf-8')

        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=10) as response:
            json_text = openmetrics_as_json(response.read().decode('utf-8'), filters) 
    except Exception as e:
        json_text = json.dumps({"error": str(e), "url": url}, indent=INDENT)
    if wrap:
        return '"%s": %s,' % (wrap, json_text)
    return json_text


def openmetrics_as_json(om_text, filters):
    def _check_name(name):
        for f in filters:
            if f in name:
                return True
        return False if filters else True

    metrics = {}
    current_metric = None
    for line in om_text.splitlines():
        line = line.strip()

        if line.startswith("# TYPE"):
            current_metric = None
            parts = line.split()
            if len(parts) >= 4:
                name, m_type = parts[2:4]
                if m_type.lower() in WANTED_TYPES and _check_name(name):
                    current_metric = [name, None]

        elif current_metric and line.startswith(current_metric[0]):
            match = METRIC_RE.match(line)
            if match:
                current_metric[1] = float(match.group(2))
                metrics[match.group(1)] = current_metric[1]
                current_metric = None

    calculate_synthetic_metrics(metrics)

    return json.dumps(metrics, indent=INDENT)


if __name__ == '__main__':
    import sys
    args = list(sys.argv[1:])
    kwargs = {}

    while '--help' in args or '-h' in args:
        print(__doc__)
        sys.exit(0) 

    for k, v in (
            ('-w', 'wrap'),     ('--wrap',     'wrap'),
            ('-u', 'username'), ('--username', 'username'),
            ('-p', 'password'), ('--password', 'password')):
        while k in args:
            idx = args.index(k) 
            kwargs[v] = args[idx + 1]
            args.pop(idx)
            args.pop(idx)

    pipe = False
    while '-' in args:
        pipe = args.pop(args.index('-'))

    if pipe or not args:
        print(openmetrics_as_json(sys.stdin.read(), args))

    else:
        url = args.pop(0)
        if os.path.exists(url):
            with open(url, 'r') as fd:
                print(openmetrics_as_json(fd.read(), args))
        else:
            if not url.startswith('http'):
                url = "http://%s/metrics" % (url,)
            print(fetch_openmetrics_as_json(url, args, **kwargs))
