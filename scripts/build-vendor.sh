#!/usr/bin/env bash
# scripts/build-vendor.sh
# Builds tui-grid + js-yaml into vendor bundles.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR="$REPO_ROOT/frontend/vendor"
WORK="/tmp/tdb-vendor"

mkdir -p "$WORK" "$VENDOR"

cd "$WORK"
npm init -y >/dev/null

npm install --save-dev \
  rollup \
  @rollup/plugin-node-resolve \
  @rollup/plugin-commonjs \
  @rollup/plugin-json \
  rollup-plugin-polyfill-node \
  @rollup/plugin-replace \
  tui-grid \
  tui-date-picker \
  tui-pagination \
  xlsx \
  js-yaml \
  codemirror@5 \
  coffeescript \
  pug

# ── Entry: tui-grid (expose as window.tui.Grid) ───────────────────────────
cat > entry-tui.js <<'JSEOF'
import Grid from 'tui-grid';
window.tui = window.tui || {};
window.tui.Grid = Grid;
JSEOF

cat > rollup-tui.mjs <<JSEOF
import resolve from "@rollup/plugin-node-resolve";
import commonjs from "@rollup/plugin-commonjs";
import json from "@rollup/plugin-json";

export default {
  input: "entry-tui.js",
  output: {
    file: "$VENDOR/tui-grid.bundle.js",
    format: "iife",
    name: "_tui_init",
  },
  plugins: [
    resolve({ browser: true, preferBuiltins: false }),
    commonjs(),
    json(),
  ],
  onwarn(w, warn) {
    if (w.code === "MODULE_LEVEL_DIRECTIVE" || w.code === "CIRCULAR_DEPENDENCY") return;
    warn(w);
  },
};
JSEOF

./node_modules/.bin/rollup -c rollup-tui.mjs

# ── CSS: tui-grid ──────────────────────────────────────────────────────────
cp node_modules/tui-grid/dist/tui-grid.css "$VENDOR/tui-grid.bundle.css"

# ── Entry: js-yaml (expose as window.jsyaml) ──────────────────────────────
cat > entry-yaml.js <<'JSEOF'
import * as yaml from 'js-yaml';
window.jsyaml = yaml;
JSEOF

cat > rollup-yaml.mjs <<JSEOF
import resolve from "@rollup/plugin-node-resolve";
import commonjs from "@rollup/plugin-commonjs";

export default {
  input: "entry-yaml.js",
  output: {
    file: "$VENDOR/jsyaml.bundle.js",
    format: "iife",
    name: "_jsyaml_init",
  },
  plugins: [resolve(), commonjs()],
};
JSEOF

./node_modules/.bin/rollup -c rollup-yaml.mjs

# ── Entry: CodeMirror v5 (core + YAML/Lua/JS/Coffee/Pug/XML/HTML modes) ───
cat > entry-cm.js <<'JSEOF'
import CodeMirror from 'codemirror/lib/codemirror';
import 'codemirror/mode/yaml/yaml';
import 'codemirror/mode/lua/lua';
import 'codemirror/mode/javascript/javascript';
import 'codemirror/mode/coffeescript/coffeescript';
import 'codemirror/mode/pug/pug';
import 'codemirror/mode/xml/xml';
import 'codemirror/mode/htmlmixed/htmlmixed';
window.CodeMirror = CodeMirror;
JSEOF

cat > rollup-cm.mjs <<JSEOF
import resolve from "@rollup/plugin-node-resolve";
import commonjs from "@rollup/plugin-commonjs";

export default {
  input: "entry-cm.js",
  output: {
    file: "$VENDOR/codemirror.bundle.js",
    format: "iife",
    name: "_cm_init",
  },
  plugins: [resolve({ browser: true }), commonjs()],
  onwarn(w, warn) {
    if (w.code === "CIRCULAR_DEPENDENCY") return;
    warn(w);
  },
};
JSEOF

./node_modules/.bin/rollup -c rollup-cm.mjs

# ── Entry: plugin runtime libs (CoffeeScript + Pug) ────────────────────────
cat > entry-plugin-runtime.js <<'JSEOF'
import CoffeeScript from 'coffeescript';
import pug from 'pug';
window.CoffeeScript = CoffeeScript;
window.pug = pug;
JSEOF

cat > rollup-plugin-runtime.mjs <<JSEOF
import resolve from "@rollup/plugin-node-resolve";
import commonjs from "@rollup/plugin-commonjs";
import json from "@rollup/plugin-json";
import nodePolyfills from "rollup-plugin-polyfill-node";

const patchProcessVersions = {
  name: 'patch-process-versions',
  renderChunk(code) {
    return code.replace(
      'var versions = {};',
      "var versions = { node: '18.0.0' };"
    );
  },
};

export default {
  input: "entry-plugin-runtime.js",
  output: {
    file: "$VENDOR/plugin-runtime.bundle.js",
    format: "iife",
    name: "_plugin_runtime_init",
  },
  plugins: [
    resolve({ browser: true, preferBuiltins: false }),
    commonjs(),
    json(),
    nodePolyfills(),
    patchProcessVersions,
  ],
  onwarn(w, warn) {
    if (w.code === "CIRCULAR_DEPENDENCY") return;
    warn(w);
  },
};
JSEOF

./node_modules/.bin/rollup -c rollup-plugin-runtime.mjs

# ── CSS: CodeMirror core + monokai theme ──────────────────────────────────
cat node_modules/codemirror/lib/codemirror.css \
    node_modules/codemirror/theme/monokai.css \
  > "$VENDOR/codemirror.bundle.css"

echo "Done:"
echo "  $VENDOR/tui-grid.bundle.js"
echo "  $VENDOR/tui-grid.bundle.css"
echo "  $VENDOR/jsyaml.bundle.js"
echo "  $VENDOR/codemirror.bundle.js"
echo "  $VENDOR/codemirror.bundle.css"
echo "  $VENDOR/plugin-runtime.bundle.js"
