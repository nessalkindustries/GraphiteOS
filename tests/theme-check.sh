#!/bin/bash
# Static theme pipeline check (no VM). Every shipped theme must have the same keys, every
# template key must exist, and rendering must leave no {{placeholder}} behind.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)/graphite; fails=0
ref=$(grep -oE '^[a-z_0-9]+' "$R/themes/graphite-teal/colors.toml" | sort | tr '\n' ' ')
for t in "$R"/themes/*/; do
  n=$(basename "$t"); keys=$(grep -oE '^[a-z_0-9]+' "$t/colors.toml" | sort | tr '\n' ' ')
  [ "$keys" = "$ref" ] || { echo "FAIL $n: keys differ from graphite-teal"; fails=$((fails+1)); }
  h=$(mktemp -d)
  HOME=$h GRAPHITE_PATH=$R bash -c 'source <(sed "/^case\|^main\|^\"\$@\"/,\$d" "$1/bin/graphite-theme"); render "$2"' _ "$R" "$t" 2>/dev/null
  left=$(grep -rlE '\{\{[a-z_0-9.]+\}\}' "$h/.config" 2>/dev/null)
  cnt=$(find "$h/.config/graphite/current" -type f 2>/dev/null | wc -l)
  if [ -n "$left" ] || [ "$cnt" -lt 5 ]; then echo "FAIL $n: unrendered=[$left] files=$cnt"; fails=$((fails+1)); else echo "ok   $n ($cnt files)"; fi
  rm -rf "$h"
done
echo "theme-check fails=$fails"; exit $((fails>0))
