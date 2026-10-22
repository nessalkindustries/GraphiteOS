# shellcheck shell=bash
# Copy the packaged defaults (/etc/skel, from graphite-config) into an existing
# user's home. Files the user changed are kept as <file>.bak.<timestamp>.
stamp=$(date +%Y%m%d%H%M%S)
src_root=/etc/skel/.config
[[ -d $src_root/hypr ]] || src_root="$GRAPHITE_PATH/config"   # before graphite-config is installed
cfg="$TARGET_HOME/.config"
as_user mkdir -p "$cfg"
while IFS= read -r -d '' src; do
  rel=${src#"$src_root/"}
  dst="$cfg/$rel"
  as_user mkdir -p "$(dirname "$dst")"
  if [[ -e $dst ]] && [[ $(sha256sum <"$src") != $(sha256sum <"$dst") ]]; then
    as_user cp -a "$dst" "$dst.bak.$stamp"
    warn "backed up $dst -> $dst.bak.$stamp"
  fi
  as_user cp -f "$src" "$dst"
  if [[ -x $src ]]; then as_user chmod +x "$dst"; fi
done < <(find "$src_root" -type f -print0)
# Generate theme-dependent files (~/.config/graphite/current) for the default theme.
if command -v graphite-theme >/dev/null; then as_user graphite-theme apply || warn "theme apply failed"; fi
