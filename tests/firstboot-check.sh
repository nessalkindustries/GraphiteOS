#!/usr/bin/env bash
# Box-level checks for first-boot setup: optional Performance kernel (linux-zen)
# checkbox and CLI. No VM, no package installs, no sudo.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
FB=$R/graphite/bin/graphite-firstboot
QML=$R/graphite/config/quickshell/graphite-firstboot/shell.qml
fails=0
ok=0
has() {
  local hay=$1 needle=$2 label=$3
  if [ -f "$hay" ]; then
    grep -qF -- "$needle" "$hay"
  else
    grep -qF -- "$needle" <<<"$hay"
  fi
  if [ $? -eq 0 ]; then echo "ok   $label"; ok=$((ok+1)); else echo "FAIL $label (missing: $needle)"; fails=$((fails+1)); fi
}

echo "== CLI =="
out=$("$FB" kernel 2>&1) || true
if [ "$out" = "zen=available" ] || [ "$out" = "zen=installed" ]; then
  echo "ok   kernel status is $out"; ok=$((ok+1))
else
  echo "FAIL kernel status: [$out]"; fails=$((fails+1))
fi
out2=$("$FB" kernel status 2>&1) || true
if [ "$out2" = "$out" ]; then echo "ok   kernel status matches bare kernel"; ok=$((ok+1))
else echo "FAIL kernel status vs bare: [$out2] vs [$out]"; fails=$((fails+1)); fi

err=$("$FB" kernel bogus 2>&1); rc=$?
if [ "$rc" -ne 0 ] && grep -q 'usage: graphite-firstboot kernel' <<<"$err"; then
  echo "ok   unknown kernel subcommand is rejected"; ok=$((ok+1))
else
  echo "FAIL unknown kernel subcommand rc=$rc err=[$err]"; fails=$((fails+1))
fi

help=$("$FB" --help 2>&1 || true)
has "$help" "graphite-firstboot kernel" "help mentions kernel"
has "$help" "linux-zen" "help mentions linux-zen"
has "$FB" "sudo graphite perf kernel zen" "CLI install path runs graphite perf kernel zen"
if grep -q 'remain the default' "$FB"; then
  echo "ok   CLI comments keep linux as the default"; ok=$((ok+1))
else
  echo "FAIL CLI does not say linux stays the default"; fails=$((fails+1))
fi
# zen is added; the default GRUB entry is not switched to it
if grep -E 'grub-set-default|boot-once|grub-reboot' "$FB" | grep -vq '^[[:space:]]*#'; then
  echo "FAIL CLI changes the default GRUB entry"; fails=$((fails+1))
else
  echo "ok   CLI does not change the default GRUB entry"; ok=$((ok+1))
fi

echo "== QML =="
has "$QML" "Performance kernel (linux-zen)" "QML label is Performance kernel (linux-zen)"
has "$QML" "GRUB Advanced options" "QML notes zen appears under GRUB Advanced options"
has "$QML" 'graphite-firstboot", "kernel", "zen"' "QML ticks run graphite-firstboot kernel zen"
has "$QML" "unchecked by default" "QML says unchecked by default"
has "$QML" "remain the default" "QML says linux remains the default"
if grep -q 'root.zen === "installed"' "$QML" && grep -q 'property string zen: ""' "$QML"; then
  echo "ok   checkbox is on only when zen is installed (starts empty / unchecked)"; ok=$((ok+1))
else
  echo "FAIL checkbox default is not unchecked"; fails=$((fails+1))
fi
if grep -A3 'id: zenP' "$QML" | grep -q 'kernel", "zen"'; then
  echo "FAIL zenP auto-runs the install"; fails=$((fails+1))
else
  echo "ok   zenP only queries status, install is on click"; ok=$((ok+1))
fi
if awk '/visible: root.step === 3/,/visible: root.step === 4/' "$QML" | grep -q 'Performance kernel (linux-zen)'; then
  echo "ok   zen option sits on the Profiles step"; ok=$((ok+1))
else
  echo "FAIL zen option is not on the Profiles step"; fails=$((fails+1))
fi

echo "== docs =="
has "$R/README.md" "optional Performance kernel (linux-zen)" "README first-boot mentions the option"
has "$R/README.md" "GRUB Advanced options" "README mentions GRUB Advanced options"
has "$R/README.md" "unchecked checkbox in first-boot setup" "README perf options mention the first-boot checkbox"
has "$R/docs/hardware-test-checklist.md" "Performance kernel (linux-zen)" "hardware checklist mentions the option"

echo "== package =="
rel=$(grep -E '^pkgrel=' "$R/graphite/pkgs/graphite-config/PKGBUILD")
if [ "$rel" = "pkgrel=31" ]; then echo "ok   graphite-config pkgrel=31"; ok=$((ok+1))
else echo "FAIL expected pkgrel=31, got $rel"; fails=$((fails+1)); fi

echo "firstboot-check ok=$ok fails=$fails"
exit $((fails>0))
