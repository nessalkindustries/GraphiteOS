#!/usr/bin/env python3
"""Pure helpers for the Graphite QEMU harness.

Argument parsing, check-group selection, and TEST-ONLY package-injection
script generation. Importable without starting QEMU or binding a port.

The full `--profile desktop` run (install, snapshot/rollback boots, every
smoke section) is REQUIRED before any release and is the default. `--profile
quick` is a shorter developer path: one install, one boot, core selftest,
and a selected subset of smoke checks. `--profile full` is the *installer*
package set (gaming and the rest), not a different test length; its harness
behaviour matches desktop.

`--packages` injects locally built `.pkg.tar.zst` files into the installed
system before the selftest (pacman -U from a harness-only directory). Those
packages are marked TEST-ONLY and are never repo-add'ed into [graphite] or
copied into /var/lib/graphite/repo or a published remote.
"""
from __future__ import annotations

import argparse
import os
import shutil
import sys

PROFILES = ("desktop", "full", "quick")

# What graphite-iso-install --profile receives. quick uses the desktop
# package set; "full" here is the larger installer set, not the release test.
INSTALL_PROFILES = {"desktop": "desktop", "full": "full", "quick": "desktop"}

# Named groups a caller can pass to --checks. "core" is the selftest
# common_checks; "repo" is already part of those and is listed so callers
# can name it; "update" is the graphite-update / -Syu block (~8 min TCG).
KNOWN_GROUPS = (
    "core",
    "desktop",
    "repo",
    "update",
    "agent",
    "theme",
    "control",
    "bar-optout",
    "settings",
    "gpu",
    "audio",
    "perf",
    "gamescope",
    "obs",
    "sync",
    "theme-store",
    "apps",
    "installer",
)

DEFAULT_QUICK_GROUPS = ("core", "desktop", "repo")

SMOKE_GROUPS = frozenset({
    "desktop", "agent", "theme", "control", "bar-optout", "settings",
    "gpu", "audio", "perf", "gamescope", "obs", "sync", "theme-store",
    "apps", "installer",
})

SELFTEST_GROUPS = frozenset({"core", "repo", "update"})

INJECT_DIR = "/var/lib/graphite/harness-test-packages"
INJECT_MARKER = "/var/lib/graphite/harness-injected-packages"

# Approximate TCG times from the 2026-11-11 s17 run (America/Toronto),
# used in docs. Install 2305s; full run ~95 minutes. Quick is estimated.
TIMING = {
    "install_tcg_s": 2305,
    "full_run_min": 95,
    "full_run_span": "19:34:26-21:09:24 America/Toronto (2026-11-11 s17, TCG)",
    "update_min": 8,
    "core_smoke_min": "10-15",
    "quick_estimate_min": "50-55",
    "quick_basis": (
        "s17 TCG phases: install 2305s (~38 min) + one boot and "
        "common_checks (~2 min) + core smoke Hyprland through "
        "notifications, skipping theme switches and later heavy items "
        "(control center, waybar opt-out, settings, gamescope, OBS, "
        "theme store, apps, installer) (~10-15 min). Not timed on a "
        "real quick-profile VM run."
    ),
}


class HarnessArgError(ValueError):
    """Invalid harness arguments; qemu-install.py prints this and exits 2."""


def parse_check_list(raw):
    """Split a comma-separated --checks value into known group names."""
    if raw is None or str(raw).strip() == "":
        return []
    groups = []
    seen = set()
    for part in str(raw).replace(" ", "").split(","):
        if not part:
            continue
        if part not in KNOWN_GROUPS and part != "all":
            raise HarnessArgError(
                "unknown check group %r; known: %s" % (part, ", ".join(KNOWN_GROUPS))
            )
        if part not in seen:
            groups.append(part)
            seen.add(part)
    return groups


def resolve_groups(profile, checks):
    """Selected check groups for this run.

    desktop and full with no --checks: ['all'] (every selftest stage and
    every smoke section -- the release run). quick with no --checks:
    DEFAULT_QUICK_GROUPS. On a quick run, 'core' is always included so
    common_checks still execute.
    """
    if profile not in PROFILES:
        raise HarnessArgError("unknown profile %r" % (profile,))
    selected = parse_check_list(checks)
    if profile in ("desktop", "full"):
        return selected if selected else ["all"]
    if not selected:
        return list(DEFAULT_QUICK_GROUPS)
    if "all" in selected:
        return ["all"]
    out = []
    seen = set()
    for g in ("core",) + tuple(selected):
        if g not in seen:
            out.append(g)
            seen.add(g)
    return out


def smoke_groups_env(groups):
    """Value for GRAPHITE_SMOKE_GROUPS, or None to leave unset (full run).

    None means smoke.sh keeps its default (all sections), which is what the
    desktop/full profiles must do. A subset string skips heavy sections.
    Selftest-only groups (core, repo, update) are not smoke groups: if the
    caller selected none of the smoke groups, return 'preamble' so only the
    session setup in smoke.sh runs (Hyprland, first-boot, bar).
    """
    if groups == ["all"] or "all" in groups:
        return None
    sg = [g for g in groups if g in SMOKE_GROUPS]
    return ",".join(sg) if sg else "preamble"


def parse_package_list(items):
    """Flatten repeated --packages and comma-separated paths."""
    out = []
    for item in items or []:
        for part in str(item).split(","):
            part = part.strip()
            if not part:
                continue
            base = os.path.basename(part)
            if not (
                base.endswith(".pkg.tar.zst")
                or base.endswith(".pkg.tar.xz")
                or base.endswith(".pkg.tar.gz")
            ):
                raise HarnessArgError(
                    "not a package file: %s (want *.pkg.tar.zst)" % part
                )
            out.append(part)
    return out


def validate_packages(paths, must_exist=True):
    """Require packages to exist and have a safe basename (no path parts)."""
    out = []
    for p in paths:
        base = os.path.basename(p)
        if base != os.path.normpath(base) or "/" in base or base in (".", "..") or not base:
            raise HarnessArgError("unsafe package name: %s" % base)
        if must_exist and not os.path.isfile(p):
            raise HarnessArgError("package not found: %s" % p)
        out.append(p)
    return out


class _Parser(argparse.ArgumentParser):
    def error(self, message):
        raise HarnessArgError(message)


_EPILOG = """
profiles:
  desktop   Full release run (default): install, snapshot/rollback boots,
            every selftest and smoke check. REQUIRED before any release.
  full      Same test length as desktop; installer package set is "full"
            (gaming and the rest).
  quick     One install, one boot, core selftest, then selected smoke.
            Default --checks: core,desktop,repo. Skips extra reboots and
            heavy smoke (gamescope, OBS, theme store, control center, ...)
            unless those groups are selected.

package-only:
  Pass the last good ISO and one or more locally built packages:
    tests/qemu-install.py /path/to/graphite-YYYY.MM.DD-x86_64.iso \\
        --profile quick --packages ./graphite-config-*.pkg.tar.zst
  Packages are installed with pacman -U into the VM only, marked TEST-ONLY,
  and never added to the published [graphite] repo.

See tests/README.md for when to use each path and for expected run times.
"""


def parse_harness_args(argv=None):
    """Parse qemu-install.py arguments. Raises HarnessArgError on bad input."""
    argv = list(sys.argv[1:] if argv is None else argv)
    p = _Parser(
        prog="tests/qemu-install.py",
        description=(
            "Graphite QEMU harness: unattended ISO install, self-test boots, "
            "and desktop smoke."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=_EPILOG.strip(),
        add_help=True,
    )
    p.add_argument(
        "iso",
        nargs="?",
        help="Path to a Graphite ISO (default: newest out/graphite-2*.iso)",
    )
    p.add_argument(
        "--profile",
        choices=PROFILES,
        default="desktop",
        help="desktop (default, release), full (installer set), or quick",
    )
    p.add_argument(
        "--checks",
        default=None,
        help=(
            "Comma-separated check groups, e.g. agent,repo,update,desktop. "
            "Default for --profile quick: %s. "
            "desktop/full default is every group." % ",".join(DEFAULT_QUICK_GROUPS)
        ),
    )
    p.add_argument(
        "--packages",
        action="append",
        default=[],
        metavar="PKG",
        help=(
            "Local .pkg.tar.zst to inject as TEST-ONLY before the selftest "
            "(repeat or comma-separated). Never published."
        ),
    )
    p.add_argument("--keep-disk", action="store_true")
    p.add_argument("--smoke-only", action="store_true")
    p.add_argument("--secureboot", action="store_true")
    p.add_argument("--no-smoke", action="store_true")
    p.add_argument("--sb-only", action="store_true")
    p.add_argument("--overlay-secureboot", action="store_true")
    p.add_argument("--overlay-installer", action="store_true")
    p.add_argument("--patch-selftest", action="store_true")
    args = p.parse_args(argv)
    args.packages = validate_packages(parse_package_list(args.packages))
    args.groups = resolve_groups(args.profile, args.checks)
    args.install_profile = INSTALL_PROFILES[args.profile]
    args.quick = args.profile == "quick"
    return args


def selftest_prefix(profile, groups, packages, host):
    """Assignment lines for the served selftest.sh. Empty for a stock desktop run.

    Must be inserted *after* the shebang via apply_script_prefix: systemd
    ExecStart=/usr/local/sbin/graphite-selftest requires #! on line 1.
    """
    lines = []
    if packages:
        lines.append("HARNESS_INJECT_HOST=%s" % host)
    if profile == "quick":
        lines.append("SELFTEST_MODE=quick")
        lines.append("SELFTEST_GROUPS=%s" % ",".join(groups))
    return ("\n".join(lines) + "\n") if lines else ""


def smoke_prefix(groups):
    """Assignment lines for the served smoke.sh. Empty for a stock desktop run.

    Must be inserted after the shebang via apply_script_prefix.
    """
    env = smoke_groups_env(groups)
    if env is None:
        return ""
    return "GRAPHITE_SMOKE_GROUPS=%s\n" % env


def apply_script_prefix(script, prefix):
    """Insert prefix lines after a leading shebang. Empty prefix is a no-op.

    Returns the original string unchanged (byte-identical) when prefix is
    empty, so a desktop/full serve matches the source file. Never places
    assignments above #!: a script that does not start with #! would fail
    systemd ExecStart / kernel direct exec (q1: env lines above the shebang
    meant graphite-selftest never started).
    """
    if not prefix:
        return script
    if not prefix.endswith("\n"):
        prefix = prefix + "\n"
    if script.startswith("#!"):
        nl = script.find("\n")
        if nl < 0:
            return script + "\n" + prefix
        return script[: nl + 1] + prefix + script[nl + 1 :]
    # Source scripts always have a shebang; keep #! on line 1 if one is missing.
    return "#!/usr/bin/env bash\n" + prefix + script


# Stall guard for selftest boots (not the smoke/SB boots). After the serial
# login prompt, SELFTEST output must appear within this many seconds or the
# harness fails the boot instead of waiting out the 3-hour qemu timeout.
SELFTEST_STALL_S = 600


def login_prompt_seen(text):
    """True when the serial getty login prompt has appeared.

    Looks for ' login:' (as in 'graphite-test login:') so 'User Login
    Management' and similar systemd lines do not trigger it.
    """
    return " login:" in text


def selftest_stalled(text, now, login_at, limit=SELFTEST_STALL_S):
    """True if the login prompt was seen, no SELFTEST line yet, and limit expired."""
    if login_at is None:
        return False
    if "SELFTEST:" in text:
        return False
    return (now - login_at) >= limit


# Tokens @@HOST@@ etc. are replaced; the body is otherwise literal bash.
_INJECT_TEMPLATE = r"""#!/usr/bin/env bash
# TEST-ONLY package injection for the Graphite QEMU harness.
# Injected packages are for this VM only. They must never be published,
# repo-add'ed into [graphite], or written under /var/lib/graphite/repo.
set -euo pipefail
HOST="@@HOST@@"
PACKAGES="@@PACKAGES@@"
INJECT_DIR="@@INJECT_DIR@@"
MARKER="@@MARKER@@"
LUKS_PASS="@@LUKS_PASS@@"
FROM_LIVE=0
SYSROOT=""
for a in "$@"; do
  case $a in
    --from-live) FROM_LIVE=1 ;;
    --sysroot=*) SYSROOT=${a#--sysroot=} ;;
  esac
done

log() { echo "HARNESS-INJECT: $*"; }

# Do not run this helper in a repo-publish environment.
if [[ -n ${GRAPHITE_PUBLISH_REPO:-} ]]; then
  log "refusing to run when GRAPHITE_PUBLISH_REPO is set"
  exit 1
fi

mount_installed() {
  # After graphite-iso-install returns, /mnt is unmounted and cryptroot is closed.
  # GPT: p1 ESP, p2 LUKS2 (PARTLABEL=GraphiteRoot) -> btrfs @ @home @log @pkg @snapshots
  local disk=${HARNESS_INJECT_DISK:-/dev/vda}
  local root
  root=$(lsblk -lnpo NAME,PARTLABEL "$disk" 2>/dev/null | awk '$2=="GraphiteRoot"{print $1; exit}')
  [[ -n $root ]] || root="${disk}2"
  [[ -b $root ]] || { log "FAIL no LUKS partition on $disk"; exit 1; }
  if [[ ! -e /dev/mapper/cryptroot ]]; then
    printf '%s' "$LUKS_PASS" | cryptsetup open --key-file - "$root" cryptroot
  fi
  mkdir -p /mnt
  mount -o subvol=@ /dev/mapper/cryptroot /mnt
  mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg,.snapshots,boot}
  mount -o subvol=@home /dev/mapper/cryptroot /mnt/home
  mount -o subvol=@log /dev/mapper/cryptroot /mnt/var/log
  mount -o subvol=@pkg /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
  SYSROOT=/mnt
}

unmount_installed() {
  sync
  umount -R /mnt 2>/dev/null || { sleep 2; umount -R /mnt 2>/dev/null || umount -R -l /mnt 2>/dev/null || true; }
  cryptsetup close cryptroot 2>/dev/null || true
}

if [[ $FROM_LIVE -eq 1 ]]; then
  mount_installed
  trap unmount_installed EXIT
fi

ROOT=${SYSROOT:-}
DEST=${ROOT}${INJECT_DIR}
MARK=${ROOT}${MARKER}
mkdir -p "$DEST" "$(dirname "$MARK")"

# Fetch only from the harness HTTP tree (test-packages/), never from a repo URL.
for pkg in $PACKAGES; do
  curl -fsSL "$HOST/test-packages/$pkg" -o "$DEST/$pkg"
  # Companion signature is optional: LocalFileSigLevel is Optional, so
  # unsigned test packages are accepted. A .sig is used when the harness served one.
  if curl -fsSL "$HOST/test-packages/${pkg}.sig" -o "$DEST/${pkg}.sig"; then
    :
  else
    rm -f "$DEST/${pkg}.sig"
  fi
done

# pacman -U on local files only. Never repo-add, never -Sy, never a [graphite] Server.
PACMAN=(pacman)
if [[ -n $ROOT ]]; then
  PACMAN+=( --sysroot "$ROOT" )
fi
shopt -s nullglob
pkgs=( "$DEST"/*.pkg.tar.zst "$DEST"/*.pkg.tar.xz "$DEST"/*.pkg.tar.gz )
shopt -u nullglob
if [[ ${#pkgs[@]} -eq 0 ]]; then
  log "FAIL no package files in $DEST"
  exit 1
fi
"${PACMAN[@]}" -U --noconfirm --needed "${pkgs[@]}"

{
  echo "TEST-ONLY: injected by the Graphite QEMU harness; not from the published [graphite] repo."
  echo "These packages must never be published or mixed into the on-disk [graphite] repo."
  date -u +"injected_at=%Y-%m-%dT%H:%M:%SZ"
  for pkg in $PACKAGES; do
    echo "package=$pkg"
  done
} > "$MARK"
chmod 644 "$MARK"
log "ok injected: $PACKAGES (marker $MARKER)"
"""


def generate_inject_script(package_basenames, host="@HOST@", luks_pass="graphite-luks"):
    """Return a bash script that pacman -U's TEST-ONLY packages.

    The script can run on the live ISO after install (`--from-live`: remount
    LUKS+btrfs and pacman --sysroot /mnt -U) or on the already-booted
    installed system (plain pacman -U). It never calls repo-add, never
    writes /var/lib/graphite/repo, and never talks to a published remote.
    """
    if not package_basenames:
        raise HarnessArgError("--packages is empty")
    names = []
    for n in package_basenames:
        base = os.path.basename(n)
        if base != n or "/" in n or n.startswith("-") or "\n" in n or "'" in n or '"' in n:
            raise HarnessArgError("unsafe package name: %s" % n)
        if not (
            base.endswith(".pkg.tar.zst")
            or base.endswith(".pkg.tar.xz")
            or base.endswith(".pkg.tar.gz")
        ):
            raise HarnessArgError("not a package file: %s" % n)
        names.append(base)
    script = _INJECT_TEMPLATE
    script = script.replace("@@HOST@@", host)
    script = script.replace("@@PACKAGES@@", " ".join(names))
    script = script.replace("@@INJECT_DIR@@", INJECT_DIR)
    script = script.replace("@@MARKER@@", INJECT_MARKER)
    script = script.replace("@@LUKS_PASS@@", luks_pass)
    return script


def stage_packages(www, package_paths, host):
    """Copy packages into www/test-packages/ and write inject-packages.sh.

    Never creates or writes www/repo/ (that path is the harness-served
    [graphite] repo and must stay a signed, publish-shaped tree).
    """
    paths = validate_packages(package_paths, must_exist=True)
    dest = os.path.join(www, "test-packages")
    os.makedirs(dest, exist_ok=True)
    names = []
    for p in paths:
        base = os.path.basename(p)
        shutil.copy2(p, os.path.join(dest, base))
        names.append(base)
        sig = p + ".sig"
        if os.path.isfile(sig):
            shutil.copy2(sig, os.path.join(dest, base + ".sig"))
    script = generate_inject_script(names, host=host)
    script_path = os.path.join(www, "inject-packages.sh")
    with open(script_path, "w", encoding="utf-8") as f:
        f.write(script)
    os.chmod(script_path, 0o755)
    return {"names": names, "script_path": script_path, "dest_dir": dest}


__all__ = [
    "PROFILES",
    "INSTALL_PROFILES",
    "KNOWN_GROUPS",
    "DEFAULT_QUICK_GROUPS",
    "SMOKE_GROUPS",
    "SELFTEST_GROUPS",
    "INJECT_DIR",
    "INJECT_MARKER",
    "TIMING",
    "HarnessArgError",
    "parse_check_list",
    "resolve_groups",
    "smoke_groups_env",
    "parse_package_list",
    "validate_packages",
    "parse_harness_args",
    "selftest_prefix",
    "smoke_prefix",
    "apply_script_prefix",
    "SELFTEST_STALL_S",
    "login_prompt_seen",
    "selftest_stalled",
    "generate_inject_script",
    "stage_packages",
]
