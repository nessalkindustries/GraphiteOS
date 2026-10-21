# shellcheck shell=bash
# Deploy default dotfiles into the user's ~/.config. Files the user changed are
# kept as <file>.bak.<timestamp> before being replaced.
stamp=$(date +%Y%m%d%H%M%S)
cfg="$TARGET_HOME/.config"
as_user mkdir -p "$cfg"
while IFS= read -r -d '' src; do
  rel=${src#"$GRAPHITE_PATH/config/"}
  dst="$cfg/$rel"
  as_user mkdir -p "$(dirname "$dst")"
  if [[ -e $dst ]] && [[ $(sha256sum <"$src") != $(sha256sum <"$dst") ]]; then
    as_user cp -a "$dst" "$dst.bak.$stamp"
    warn "backed up $dst -> $dst.bak.$stamp"
  fi
  as_user cp -f "$src" "$dst"
  if [[ -x $src ]]; then as_user chmod +x "$dst"; fi
done < <(find "$GRAPHITE_PATH/config" -type f -print0)
