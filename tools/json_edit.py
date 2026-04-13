#!/usr/bin/env python3
"""\
Usage: json_set.py /path/to/file.json [path/to/var op value]*

Paths are used to traverse a tree of dictionaries and find a variable.

Operations are:
    =   set       # Set a variable
    >=  max       # Set a variable if new value is bigger
    <=  min       # Set a variable if new value is smaller
    +=  addition  # Int/Float addition
    -=  subtract  # Int/Float subraction
    |=  add       # Add if not present to a list/set
        append    # Append to a list (duplicates allowed)
        bound     # Bound a list, keeping the last N events
        sort      # Sort a list, descending if N is negative

Values are parsed as JSON, so they can be any of strings, ints, lists
or objects - it is up to the caller to make sure the data type matches
the operation.

Example:

    # Create an empty list and append something to it
    json_edit.py example.json \\
        'hosts/myhost/ipv4' set '[]' \\
        'hosts/myhost/ipv4' append 1.2.3.4

    # Change the zeroth element
    json_edit.py example.json \\
        'hosts/myhost/ipv4[0]' = 4.3.2.1

    # Remove the entire hosts subtree
    json_edit.py example.json \\
        . remove hosts
"""
import json
import os


class JsonSetter:
    def __init__(self, json_filename):
        self.json_filename = json_filename
        self.data = {}
        self.load()
        self.indent = int(os.getenv('JSON_INDENT', 2))

    def load(self):
        try:
            with open(self.json_filename, 'r') as fd:
                self.data = json.load(fd)
        except (OSError, IOError):
            if os.path.exists(self.json_filename):
                raise

    def save(self):
        with open(self.json_filename, 'w') as fd:
            fd.write(json.dumps(self.data, indent=self.indent))

    def do(self, target, op, value):
        dval = value
        try:
            dval = json.loads(value)
        except json.decoder.JSONDecodeError:
            pass

        data = self.data
        if target[0] == '.':
            data = {'.': data}

        path = target.split('/')
        dkey = path.pop(-1)
        didx = None
        while path:
            sub, idx = path.pop(0), None
            if sub.endswith(']'):
                sub, idx = sub[:-1].split('[')
                idx = int(idx)
                d = data[sub][idx]
            else:
                data[sub] = d = data.get(sub, {})
            data = d

        if dkey.endswith(']'):
            dkey, idx = dkey[:-1].split('[')
            if dkey not in data:
                data[dkey] = []
            if idx:
                didx = int(idx)

        changes = 0
        if op in ('=', 'set'):
            if didx is None:
                old_val, data[dkey] = data.get(dkey), dval
            else:
                old_val, data[dkey][didx] = data[dkey][didx], dval
            changes += 1 if (old_val != dval) else 0

        elif op in ('>=', 'max'):
            if didx is None:
                if data.get(dkey, 0) < dval:
                    data[dkey] = dval
                    changes += 1
            else:
                if data[dkey][didx] < dval:
                    data[dkey][didx] = dval
                    changes += 1

        elif op in ('<=', 'min'):
            if didx is None:
                if data.get(dkey, 0) > dval:
                    data[dkey] = dval
                    changes += 1
            else:
                if data[dkey][didx] > dval:
                    data[dkey][didx] = dval
                    changes += 1

        elif op == ('+=', 'addition'):
            if didx is None:
                data[dkey] += dval
            else:
                data[dkey][didx] += dval
            changes += 1

        elif op == ('-=', 'subtract'):
            if didx is None:
                data[dkey] -= dval
            else:
                data[dkey][didx] -= dval
            changes += 1

        elif op in ('|=', 'add', 'append'):
            if data.get(dkey):
                if didx is not None:
                    if (dval not in data[dkey][didx]) or (op == 'append'):
                        data[dkey][didx].append(dval)
                        changes += 1
                elif (dval not in data[dkey]) or (op == 'append'):
                    data[dkey].append(dval)
                    changes += 1
            elif didx is not None:
                raise KeyError('Cannot index into non-existant array: %s' % target)
            else:
                data[dkey] = [dval]
                changes += 1

        elif op in ('^=', 'rm', 'remove'):
            if dkey in data:
                if didx is not None:
                    while dval in data[dkey][didx]:
                        if isinstance(data[dkey][didx], dict):
                            del data[dkey][didx][dval]
                        else:
                            data[dkey][didx].remove(dval)
                        changes += 1
                else:
                    while dval in data.get(dkey, {}):
                        if isinstance(data[dkey], dict):
                            del data[dkey][dval]
                        else:
                            data[dkey].remove(dval)
                        changes += 1

        elif op == 'bound':
            if dkey in data:
                lst = None
                if didx is not None:
                    lst = data[dkey][didx]
                else:
                    lst = data[dkey]
                while len(lst) > dval:
                    lst.pop(0)
                    changes += 1

        elif op == 'sort':
            if dkey in data:
                lst = None
                if didx is not None:
                    lst = data[dkey][didx]
                else:
                    lst = data[dkey]
                lst.sort()
                if dval < 0:
                    lst.reverse()

        else:
            raise ValueError('Unknown operation: %s' % op)

        if changes and not path and dkey == '.':
            self.data = data['.']

        return changes


if __name__ == '__main__':
    import sys
    if len(sys.argv) < 5:
        print(__doc__)
        sys.exit(1)
    args = list(sys.argv[1:])
    fn = args.pop(0)
    js = JsonSetter(fn)
    changes = 0
    while args:
        (target, op, value), args = args[:3], args[3:]
        changes += js.do(target, op, value)
    if changes:
        js.save()
        print('CHANGED=%s' % fn)
