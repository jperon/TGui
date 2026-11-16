#!/usr/bin/env bash
# Vérifie l'environnement de développement Nix « gravé dans le marbre ».
# À lancer DANS le dev shell, ou via `make doctor` (qui entre dans le shell
# si nécessaire). Aucune dépendance externe : uniquement des outils du shell.
# Code de sortie non nul au moindre écart.
set -u

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root" || exit 1

fail=0
ok()   { printf '  OK    %s\n' "$*"; }
bad()  { printf '  ÉCHEC %s\n' "$*"; fail=1; }
warn() { printf '  AVERT %s\n' "$*"; }

echo "== Outils =="
for tool in lua coffee node make; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool -> $(command -v "$tool")"
  else
    bad "$tool introuvable dans le PATH"
  fi
done

# Le compilateur MoonScript est celui du sous-module backend/vendor/moonscript
# (tag v0.8.0), exécuté par le Lua du dev shell : même version qu'à l'exécution.
if [ -f "$repo_root/backend/vendor/moonscript/bin/moonc" ]; then
  ok "sous-module backend/vendor/moonscript présent"
  printf '  version moonc/moonscript : %s\n' "$("$repo_root/scripts/moonc.sh" -v 2>&1)"
else
  bad "sous-module absent : lancer 'git submodule update --init'"
fi
for mod in lpeg argparse lfs; do
  if lua -e "require('$mod')" >/dev/null 2>&1; then
    ok "module Lua $mod"
  else
    bad "module Lua $mod introuvable (moonc en dépend)"
  fi
done
command -v coffee >/dev/null 2>&1 && printf '  version coffee : %s\n' "$(coffee --version 2>&1)"
command -v node   >/dev/null 2>&1 && printf '  version node   : %s\n' "$(node --version 2>&1)"
command -v make   >/dev/null 2>&1 && printf '  version make   : %s\n' "$(make --version 2>&1 | head -1)"

echo "== Hermétisme (aucune bibliothèque de l'hôte) =="
for var in LD_LIBRARY_PATH LD_PRELOAD LD_AUDIT; do
  val=$(printenv "$var" 2>/dev/null || true)
  if [ -n "$val" ]; then
    bad "$var non vide : $val"
  else
    ok "$var vide"
  fi
done

echo "== Playwright (driver JS aligné sur les navigateurs Nix) =="
expected="${PLAYWRIGHT_VERSION:-}"
installed=$(node -e "try{console.log(require('./node_modules/playwright-core/package.json').version)}catch(e){process.exit(3)}" 2>/dev/null || true)
if [ -z "$installed" ]; then
  warn "playwright-core non installé (node_modules absent ?) : lancer 'npm ci'"
elif [ -z "$expected" ]; then
  warn "PLAYWRIGHT_VERSION non défini (hors dev shell ?) ; installé = $installed"
elif [ "$installed" = "$expected" ]; then
  ok "playwright-core $installed == Nix $expected"
else
  bad "playwright-core $installed != Nix $expected"
fi

echo "== Navigateur headless =="
if [ -n "$installed" ]; then
  if node -e '
    const pw = require("./node_modules/playwright-core");
    (async () => {
      const b = await pw.chromium.launch({ headless: true });
      const p = await b.newPage();
      await p.goto("about:blank");
      await p.title();
      await b.close();
    })().catch(e => { console.error(String(e).split("\n")[0]); process.exit(1); });
  '; then
    ok "chromium headless démarre"
  else
    bad "chromium headless ne démarre pas"
  fi
else
  warn "playwright-core non résolvable : navigateur non testé"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "doctor: environnement conforme"
  exit 0
fi
echo "doctor: écarts détectés"
exit 1
