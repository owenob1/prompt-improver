#!/usr/bin/env python3
"""Split an instructions file (CLAUDE.md, AGENTS.md…) into sentence-level rule units, one per line."""
import re, sys
txt = re.sub(r'```.*?```', '', open(sys.argv[1]).read(), flags=re.S)
for p in re.split(r'\n\s*\n', txt):
    p = p.strip()
    if not p or p.startswith('#') or p.startswith('|'):
        continue
    for s in re.split(r'(?<=[.!?])\s+(?=[A-Z`*])', re.sub(r'\s+', ' ', p)):
        if len(s.strip()) > 30:
            print(s.strip())
