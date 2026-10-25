#!/usr/bin/env bash
# Static checks for .github: every workflow is manual-trigger only (workflow_dispatch), read-only
# token, no release publishing; issue forms are valid YAML. Uses actionlint if installed.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import glob, sys, yaml
bad = 0
for f in sorted(glob.glob('.github/workflows/*.y*ml')):
    w = yaml.safe_load(open(f))
    on = w.get(True, w.get('on'))  # PyYAML parses the key `on` as True
    keys = set(on) if isinstance(on, dict) else {on} if isinstance(on, str) else set(on)
    if keys != {'workflow_dispatch'}: print(f"FAIL {f}: triggers {sorted(map(str, keys))}, want only workflow_dispatch"); bad += 1
    if w.get('permissions') != {'contents': 'read'}: print(f"FAIL {f}: permissions must be contents: read"); bad += 1
    txt = open(f).read()
    for word in ('gh release', 'softprops/action-gh-release', 'actions/create-release', 'secrets.'):
        if word in txt: print(f"FAIL {f}: uses {word}"); bad += 1
    print(f"ok   {f}")
for f in sorted(glob.glob('.github/ISSUE_TEMPLATE/*.y*ml')):
    d = yaml.safe_load(open(f))
    if f.endswith('config.yml'): print(f"ok   {f}"); continue
    for k in ('name', 'description', 'body'):
        if k not in d: print(f"FAIL {f}: missing {k}"); bad += 1
    ids = [b['id'] for b in d['body'] if 'id' in b]
    if len(ids) != len(set(ids)): print(f"FAIL {f}: duplicate ids"); bad += 1
    print(f"ok   {f}")
sys.exit(1 if bad else 0)
PY
if command -v actionlint >/dev/null; then actionlint && echo "ok   actionlint"; else echo "skip actionlint (not installed)"; fi
