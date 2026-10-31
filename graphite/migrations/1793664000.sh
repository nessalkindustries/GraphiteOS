#!/bin/bash
# desk-8 fetch: logo to the left of the boxes (falls back to on top in narrow windows).
# An unedited desk-8 fetch config is replaced (with a .bak); an edited one is kept and the
# new default is written next to it as config.jsonc.graphite-new.
echo "Graphite: fetch logo now sits left of the system info"
new=/etc/skel/.config/fastfetch/config.jsonc f=$HOME/.config/fastfetch/config.jsonc
defaults="2496cea1ca4261ef458e928499a19eaeecb234e2314827bd3df82a26f1a9c022 2bd9a744e9440eb7acfd9c17ba60f5e7f335caa53d63e6b6791cfff3028ff9d3"
[[ -f $new && -f $f ]] || exit 0
cmp -s "$new" "$f" && exit 0
if [[ " $defaults " == *" $(sha256sum < "$f" | cut -c1-64) "* ]]; then cp -f "$f" "$f.bak"; install -m644 "$new" "$f"
else install -m644 "$new" "$f.graphite-new"; echo "  kept your edited $f; new default in $f.graphite-new"; fi
true
