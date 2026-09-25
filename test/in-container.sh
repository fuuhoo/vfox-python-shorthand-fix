#!/usr/bin/env bash
# Reproduce the shorthand bug, apply the fix, verify -- inside a container that
# already has vfox, the python plugin and two python patch versions installed.
#
# Why the nesting below looks awkward: `vfox exec` never runs the PreUse hook
# (only UseWithConfig -> preUse does) and `vfox use` refuses to switch without
# the shell hook, so every switch has to happen in an interactive
# bash. bash -i echoes the fed script back, hence the '##' markers.
set -uo pipefail

HOOK="${VFOX_HOME:-$HOME/.vfox}/plugin/python/hooks/pre_use.lua"
FAIL=0

ok()  { printf 'PASS  %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
sec() { printf '\n=== %s\n' "$1"; }

# attempt FROM TO: switch to FROM, then try TO, and print the version that ends
# up running. A rejected request leaves FROM in place, which is how the bug
# shows up as "nothing happened".
attempt() {
  WANT_FROM="$1" WANT_TO="$2" bash -il 2>&1 <<'EOS' | sed -n 's/^##VER //p' | tail -1
vfox use --global python@$WANT_FROM >/dev/null 2>&1
vfox use --global python@$WANT_TO   >/dev/null 2>&1
printf '##VER %s\n' "$(python -VV 2>&1 | head -1 | awk '{print $2}')"
EOS
}

# expect_run FROM TO WANT LABEL
expect_run() {
  local got; got="$(attempt "$1" "$2")"
  if [ "$got" = "$3" ]; then ok "$2 -> $got   ($4)"; else bad "$2 -> '${got}', expected '$3'   ($4)"; fi
}

pristine() { cp /fix/upstream/pre_use.lua.0.6.2 "$HOOK"; }

sec "0. environment"
echo "vfox   : $(vfox --version 2>&1 | head -1)"
echo "python : $(ls "${VFOX_HOME:-$HOME/.vfox}/cache/python" 2>/dev/null | tr '\n' ' ')"
[ -f "$HOOK" ] || { echo "FAIL  no python plugin hook at $HOOK"; exit 1; }

sec "1. upstream v0.6.2: shorthand is refused, full version works"
pristine
expect_run 3.9.25 3.9.25 3.9.25 "full version switches"
expect_run 3.9.25 3.12.14 3.12.14 "full version switches"
expect_run 3.9.25 3.12 3.9.25 "shorthand rejected -> stays put (the bug)"
expect_run 3.12.14 3.9 3.12.14 "shorthand rejected -> stays put (the bug)"

sec "2. patch.sh"
pristine
/fix/patch.sh "$HOOK"        || bad "patch.sh failed"
grep -q resolveInstalledVersion "$HOOK" && ok "hook now resolves shorthands" || bad "hook not patched"
/fix/patch.sh "$HOOK" >/dev/null && ok "second run is a no-op"        || bad "not idempotent"
/fix/patch.sh --check "$HOOK" >/dev/null && ok "--check sees the fix" || bad "--check wrong"
[ -f "$HOOK.orig" ] && ok "original saved as $HOOK.orig" || bad "no backup"

sec "3. fixed hook: shorthand resolves to the installed patch version"
expect_run 3.9.25   3.12     3.12.14 "python@3.12"
expect_run 3.12.14  3.9      3.9.25  "python@3.9"
expect_run 3.9.25   3.9.25   3.9.25  "exact version still works"
expect_run 3.12.14  3.12.14  3.12.14 "exact version still works"

sec "4. a shorthand with nothing installed stays refused"
expect_run 3.12.14 3.11 3.12.14 "python@3.11 not installed -> no silent switch"

sec "5. the hook still runs the shebang health check"
# A shorthand switch must not skip the health check: the resolved version has to
# go through the same path an exact switch does.
health=$(bash -il 2>&1 <<'EOS'
vfox use --global python@3.12
EOS
)
printf '%s\n' "$health"
printf '%s\n' "$health" | grep -qE 'is healthy|has minor issues|has critical issues' \
  && ok "health check ran" || bad "health check skipped"

sec "6. --restore"
/fix/patch.sh --restore "$HOOK" >/dev/null && ok "--restore ran" || bad "--restore failed"
cmp -s /fix/upstream/pre_use.lua.0.6.2 "$HOOK" && ok "hook back to upstream bytes" || bad "--restore did not revert"

printf '\n%s\n' "----------------------------------------"
[ "$FAIL" -eq 0 ] && echo "all checks passed" || echo "$FAIL check(s) failed"
exit $((FAIL > 0))
