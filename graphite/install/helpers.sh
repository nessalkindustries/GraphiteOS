# shellcheck shell=bash
# Shared helpers for install phases (sourced, not executed).
log()  { printf '\e[38;2;94;234;212m==>\e[0m %s\n' "$*"; }
warn() { printf '\e[33mwarning:\e[0m %s\n' "$*" >&2; }
# Print package names from list files, skipping comments and blank lines.
pkg_list() { sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$@"; }
# Run a command as the target user. setpriv (util-linux) instead of runuser/su:
# no PAM session, so it also works in early boot (graphite-home.service) and chroots.
as_user() {
  setpriv --reuid="$TARGET_USER" --regid="$(id -g "$TARGET_USER")" --init-groups \
    env HOME="$TARGET_HOME" USER="$TARGET_USER" LOGNAME="$TARGET_USER" "$@"
}
