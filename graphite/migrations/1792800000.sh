echo "Graphite: hide helper entries (About Xfce, Bulk Rename, rofi, Qt6 Settings, ...) from the app launcher"
# Copies the NoDisplay overrides from /etc/skel; files you already have are left alone.
dst=$HOME/.local/share/applications; mkdir -p "$dst"
for f in /etc/skel/.local/share/applications/*.desktop; do
  [[ -e $f ]] || continue
  [[ -e $dst/$(basename "$f") ]] || cp "$f" "$dst/"
done
