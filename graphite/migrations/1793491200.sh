#!/bin/bash
# desk-8: new fetch layout (boxed Hardware / Software / Age / Uptime / Update sections).
# An unedited fastfetch config is replaced (with a .bak); an edited one is kept and the
# new default is written next to it as config.jsonc.graphite-new.
echo "Graphite desk-8: new fetch layout (run 'graphite fetch' or fastfetch)"
new=/etc/skel/.config/fastfetch/config.jsonc f=$HOME/.config/fastfetch/config.jsonc
old_default=9bbd233983844df0427315051d3f6875c527dd39cfd05fd3a6480fa555546bd6
[[ -f $new ]] || exit 0
if [[ ! -f $f ]]; then install -Dm644 "$new" "$f"
elif ! cmp -s "$new" "$f"; then
  if [[ $(sha256sum < "$f" | cut -c1-64) == "$old_default" ]]; then cp -f "$f" "$f.bak"; install -m644 "$new" "$f"
  else install -m644 "$new" "$f.graphite-new"; echo "  kept your edited $f; new layout in $f.graphite-new"; fi
fi
true
