#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd -P)
core_dir="${VELUNORI_CORE_PATH:-$(dirname "$repo_dir")/core}"
layout="${VELUNORI_TEST_LAYOUT:-copy}"
[[ "$layout" == copy || "$layout" == symlink ]] || { echo 'Unknown test layout' >&2; exit 1; }
if [[ -z ${VELUNORI_PREVIEW_PATH:-} ]]; then
  # Runs a stand-in for omarchy-update in a temporary directory; never the real one.
  if [[ ${VELUNORI_TEST_UI_ONLY:-0} != 1 ]]; then
    python3 -m unittest discover -s "$repo_dir/tests" -p 'test_*.py'
  fi
  node "$repo_dir/tests/logic.test.mjs"
fi
runtime_dir=$(mktemp -d)
trap 'rm -rf "$runtime_dir"' EXIT
chmod 700 "$runtime_dir"
mkdir -p "$runtime_dir/velunori.update" "$runtime_dir/velunori.core" "$runtime_dir/imports/qs"
cp "$repo_dir/"*.qml "$repo_dir/"*.js "$repo_dir/qmldir" "$repo_dir/backend.py" "$runtime_dir/velunori.update/"
cp -r "$repo_dir/components" "$runtime_dir/velunori.update/"
cp -r "$core_dir/kit" "$core_dir/components" "$core_dir/design" "$core_dir/assets" "$runtime_dir/velunori.core/"
if [[ "$layout" == symlink ]]; then
  mkdir "$runtime_dir/checkouts"
  mv "$runtime_dir/velunori.update" "$runtime_dir/checkouts/update"
  mv "$runtime_dir/velunori.core" "$runtime_dir/checkouts/core"
  ln -s core "$runtime_dir/checkouts/velunori.core"
  ln -s "$runtime_dir/checkouts/update" "$runtime_dir/velunori.update"
  ln -s "$runtime_dir/checkouts/core" "$runtime_dir/velunori.core"
fi
shell_dir="${OMARCHY_PATH:-/usr/share/omarchy}/shell"
for module in Commons Ui; do
  ln -s "$shell_dir/$module" "$runtime_dir/imports/qs/$module"
  ln -s "$shell_dir/$module" "$runtime_dir/$module"
done
/usr/lib/qt6/bin/qmllint -I "$runtime_dir/imports" --unqualified info --missing-property warning --incompatible-type info \
  "$runtime_dir/velunori.update/"*.qml "$runtime_dir/velunori.update/components/"*.qml > "$runtime_dir/lint.log" 2>&1 || { cat "$runtime_dir/lint.log"; exit 1; }
if rg -q 'Failed to import|was not found|is not a type' "$runtime_dir/lint.log"; then cat "$runtime_dir/lint.log"; exit 1; fi
cp "$repo_dir/tests/ui.qml" "$runtime_dir/shell.qml"
env -u WAYLAND_DISPLAY -u DISPLAY XDG_RUNTIME_DIR="$runtime_dir" XDG_CONFIG_HOME="$runtime_dir/config" XDG_STATE_HOME="$runtime_dir/state" XDG_CACHE_HOME="$runtime_dir/cache" \
  QML_IMPORT_PATH="$runtime_dir/imports" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_CONTROLS_STYLE=Basic QT_QUICK_BACKEND=software \
  timeout 15s quickshell -p "$runtime_dir/shell.qml" --no-color > "$runtime_dir/ui.log" 2>&1 || { cat "$runtime_dir/ui.log"; exit 1; }
cat "$runtime_dir/ui.log"
if rg -q 'UPDATE_TEST_FAILED|Failed to load|TypeError|ReferenceError|Binding loop|Unable to assign|Ignoring unresolvable import.*velunori' "$runtime_dir/ui.log"; then exit 1; fi
if [[ -n ${VELUNORI_PREVIEW_PATH:-} ]]; then rg -q 'UPDATE_PREVIEW_SAVED' "$runtime_dir/ui.log"; exit; fi
rg -q 'UPDATE_TEST_PASSED' "$runtime_dir/ui.log"
