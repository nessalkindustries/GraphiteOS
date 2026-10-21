# shellcheck shell=bash
# Shared helpers for install phases (sourced, not executed).
log()  { printf '\e[38;2;94;234;212m==>\e[0m %s\n' "$*"; }
warn() { printf '\e[33mwarning:\e[0m %s\n' "$*" >&2; }
# Print package names from list files, skipping comments and blank lines.
pkg_list() { sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$@"; }
# Run a command as the target user.
as_user() { runuser -u "$TARGET_USER" -- "$@"; }
