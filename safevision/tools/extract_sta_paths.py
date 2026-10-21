#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Extract per-path detail from TD route.timing.

Block model: each path starts at a line 'Slack               : <val>ns'.
Within a block: 'Begin Point', 'End Point', 'Check Type', 'Data Path Delay'
and a cell table (lines with LUT/route rows).

Usage:
  python extract_sta_paths.py <route.timing> [--neg] [--ends SUBSTR ...] [--cells]
  --neg          : only negative-slack setup blocks
  --ends S1 S2   : only blocks whose End Point contains any of the substrings
  --cells        : print the cell/net table of each matched block
"""
import re
import sys

def load_blocks(path):
    txt = open(path, 'r', errors='replace').read()
    # split on 'Slack               : ' block headers (exactly this report style)
    idxs = [m.start() for m in re.finditer(r'^Slack\s+:\s*[-\d.]+ns\s*$', txt, re.M)]
    blocks = []
    for i, s in enumerate(idxs):
        e = idxs[i + 1] if i + 1 < len(idxs) else len(txt)
        blocks.append(txt[s:e])
    return blocks

def field(block, name):
    m = re.search(r'^%s\s+:\s*(.+)$' % re.escape(name), block, re.M)
    return m.group(1).strip() if m else ''

def slack_of(block):
    m = re.match(r'^Slack\s+:\s*([-\d.]+)ns', block)
    return float(m.group(1)) if m else None

def cell_table(block):
    """Return the cell/net detail lines (rows of the path table)."""
    rows = []
    for ln in block.splitlines():
        s = ln.strip()
        if not s or s.startswith('Slack') or s.startswith('Begin Point') or \
           s.startswith('End Point') or s.startswith('Check Type') or \
           s.startswith('Data Path') or s.startswith('---') or \
           s.startswith('Location') or s.startswith('Logic') or \
           s.startswith('Clock') or s.startswith('Launch') or \
           s.startswith('Capture') or s.startswith('Required') or \
           s.startswith('Arrival') or re.match(r'^Slack\s+[-\d.]+$', s):
            continue
        rows.append(ln.rstrip())
    return rows

def main():
    args = sys.argv[1:]
    path = args[0]
    neg_only = '--neg' in args
    want_cells = '--cells' in args
    mem_only = '--mem' in args
    top_n = None
    if '--top' in args:
        top_n = int(args[args.index('--top') + 1])
    end_subs = []
    if '--ends' in args:
        i = args.index('--ends')
        for a in args[i + 1:]:
            if a.startswith('--'):
                break
            end_subs.append(a)

    blocks = load_blocks(path)
    matched = []
    for b in blocks:
        sl = slack_of(b)
        if sl is None:
            continue
        ck = field(b, 'Check Type')
        ep = field(b, 'End Point')
        bp = field(b, 'Begin Point')
        if neg_only and not (sl < 0 and 'setup' in ck):
            continue
        if mem_only:
            if 'setup' not in ck:
                continue
            bclk = field(b, 'Begin Point')
            eclk = field(b, 'End Point')
            if 'clkc[1]' not in bclk or 'clkc[1]' not in eclk:
                continue
            if 'sdram' in ep or 'sdram' in bp:
                continue
        if end_subs and not any(s in ep for s in end_subs):
            continue
        matched.append((sl, bp, ep, ck, b))

    matched.sort(key=lambda t: t[0])
    if top_n is not None:
        matched = matched[:top_n]
    for sl, bp, ep, ck, b in matched:
        print('#' * 70)
        print('Slack      : %.3f ns   [%s]' % (sl, ck))
        print('Begin      : %s' % bp)
        print('End        : %s' % ep)
        print('Delay      : %s' % field(b, 'Data Path Delay'))
        if want_cells:
            print('--- cell/net rows ---')
            for ln in cell_table(b):
                print(ln)
    print('total matched: %d' % len(matched))

if __name__ == '__main__':
    main()
