#!/bin/sh
# Run the real core without the game's autoloads, textures, audio or scenes.
set -eu
: "${GODOT_BIN:?Set GODOT_BIN to the exact Godot 4.7.2 executable}"
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PURE="$ROOT/.local/battle-pure"
PRIVATE="$ROOT/.local/battle-tests"
mkdir -p "$PURE" "$PRIVATE/home" "$PRIVATE/cache" "$PRIVATE/config" "$PRIVATE/data"
export XDG_CACHE_HOME="$PRIVATE/cache" XDG_CONFIG_HOME="$PRIVATE/config" XDG_DATA_HOME="$PRIVATE/data"
case "$("$GODOT_BIN" --version)" in
  4.7.2|4.7.2.stable|4.7.2.stable.*) ;;
  *) printf '%s\n' 'Pure battle tests require Godot 4.7.2; no fallback attempted.' >&2; exit 1 ;;
esac
printf 'config_version=5\n[application]\nconfig/name="Keepsake Pure Battle Tests"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n' > "$PURE/project.godot"
ln -sfn ../../scripts "$PURE/scripts"
ln -sfn ../../tests "$PURE/tests"
if env KEEPSAKE_CONTENT_ROOT="$ROOT/data" XDG_CACHE_HOME="$PRIVATE/cache" XDG_CONFIG_HOME="$PRIVATE/config" XDG_DATA_HOME="$PRIVATE/data" "$GODOT_BIN" --headless --path "$PURE" --script res://tests/battle/battle_runner.gd > "$PRIVATE/pure.log" 2>&1; then
  status=0
else
  status=$?
fi
cat "$PRIVATE/pure.log"
if [ "$status" -ne 0 ] || grep -Eq '^(SCRIPT ERROR:|ERROR:)' "$PRIVATE/pure.log"; then
  exit 1
fi
grep -Eq '^D1_BATTLE_TEST_RESULT: .*"failed":0.*"passed":[1-9][0-9]*' "$PRIVATE/pure.log"
