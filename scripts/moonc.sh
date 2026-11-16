#!/usr/bin/env bash
# Lance le compilateur MoonScript du sous-module backend/vendor/moonscript.
#
# Le compilateur est celui du sous-module (tag v0.8.0) et non celui de
# nixpkgs : c'est exactement la version qui tourne dans Tarantool à
# l'exécution (`moonscript.base.to_lua` pour les formules). Il s'exécute sur
# l'interpréteur Lua 5.1 du dev shell Nix ($TGUI_LUA, fourni par flake.nix),
# qui apporte lpeg, argparse et luafilesystem, avec l'analyseur natif compilé
# par le Makefile dans build/ (LUA_CPATH).
#
# Usage : scripts/moonc.sh [options de moonc] fichier.moon
#          scripts/moonc.sh -v
set -u

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ms="$root/backend/vendor/moonscript"
lua=${TGUI_LUA:-lua5.1}

if [ ! -f "$ms/bin/moonc" ]; then
  echo "❌ moonc introuvable : lancer 'git submodule update --init'" >&2
  exit 1
fi

exec env \
  LUA_PATH="$ms/?.lua;$ms/?/init.lua;;" \
  LUA_CPATH="$root/build/?.so;;" \
  "$lua" "$ms/bin/moonc" "$@"
