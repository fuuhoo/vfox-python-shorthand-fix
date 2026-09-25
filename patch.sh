#!/usr/bin/env bash
# Apply (or undo) the shorthand-version fix to an installed vfox-python plugin.
#
#   ./patch.sh                      # patch $VFOX_HOME/plugin/python/hooks/pre_use.lua
#   ./patch.sh /path/to/pre_use.lua # patch an explicit file
#   ./patch.sh --check              # exit 0 if already fixed, 1 if not
#   ./patch.sh --restore            # put the backed-up original back
#
# Idempotent: running it twice leaves one backup and the same result.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixed="$repo/hooks/pre_use.lua"
target="${VFOX_HOME:-$HOME/.vfox}/plugin/python/hooks/pre_use.lua"
mode=apply

for arg in "$@"; do
  case "$arg" in
    --check)   mode=check ;;
    --restore) mode=restore ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)         target="$arg" ;;
  esac
done

[ -f "$target" ] || { echo "patch.sh: no plugin hook at $target (run 'vfox add python' first)" >&2; exit 1; }

if [ "$mode" = restore ]; then
  [ -f "$target.orig" ] || { echo "patch.sh: nothing to restore, $target.orig is missing" >&2; exit 1; }
  cp -p "$target.orig" "$target"
  echo "patch.sh: restored $target from $target.orig"
  exit 0
fi

if [ "$mode" = check ]; then
  if grep -q 'resolveInstalledVersion' "$target"; then echo "patch.sh: already fixed"; exit 0; fi
  echo "patch.sh: not fixed" >&2
  exit 1
fi

if grep -q 'resolveInstalledVersion' "$target"; then
  echo "patch.sh: already fixed, nothing to do"
  exit 0
fi

# Refuse to touch a hook we do not recognise: a future plugin rewrite may move
# the shebang logic and a blind overwrite would break it silently.
grep -q 'function PLUGIN:PreUse' "$target" || {
  echo "patch.sh: $target has no PLUGIN:PreUse -- not a vfox-python hook, refusing" >&2
  exit 1
}

[ -f "$target.orig" ] || cp -p "$target" "$target.orig"
cp "$fixed" "$target"
echo "patch.sh: patched $target (original kept as $target.orig)"
echo "patch.sh: verify with  vfox use --global python@<major>.<minor>"
