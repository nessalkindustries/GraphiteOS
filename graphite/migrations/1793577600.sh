#!/bin/bash
# desk-8 fetch fix: the Graphite logo is back next to the fetch, and the font line no longer
# asks kitty over escape codes (late replies showed up as garbage on the prompt).
# An unedited desk-8 fetch config is replaced (with a .bak); an edited one is kept and the
# fixed default is written next to it as config.jsonc.graphite-new.
echo "Graphite: fetch logo restored, no more escape-code garbage after fastfetch"
new=/etc/skel/.config/fastfetch/config.jsonc f=$HOME/.config/fastfetch/config.jsonc
desk8_default=2496cea1ca4261ef458e928499a19eaeecb234e2314827bd3df82a26f1a9c022
[[ -f $new && -f $f ]] || exit 0
cmp -s "$new" "$f" && exit 0
if [[ $(sha256sum < "$f" | cut -c1-64) == "$desk8_default" ]]; then cp -f "$f" "$f.bak"; install -m644 "$new" "$f"
else install -m644 "$new" "$f.graphite-new"; echo "  kept your edited $f; fixed default in $f.graphite-new"; fi
true
