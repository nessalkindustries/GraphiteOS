# shellcheck shell=bash
# Fresh setups already have the current configs: mark every migration as done
# for this user, so `graphite update` only runs newer ones.
migrate=$(command -v graphite-migrate || echo "$GRAPHITE_PATH/bin/graphite-migrate")
as_user "$migrate" --mark-all-done
