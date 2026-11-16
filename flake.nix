{
  description = "TGui — GUI web pour Tarantool 3 (dev shell : build, tests, navigateur)";

  # Entrées ÉPINGLÉES : l'URL pointe la révision exacte déjà figée dans
  # flake.lock, de sorte que flake.nix et flake.lock disent la même chose et
  # qu'un `nix flake update` accidentel ne fasse pas glisser l'environnement.
  #
  # Mise à jour VOLONTAIRE : remplacer la révision ci-dessous par celle de la
  # branche voulue, par exemple
  #   nix flake update --override-input nixpkgs github:NixOS/nixpkgs/nixos-unstable
  # puis re-épingler ici la nouvelle `rev` lue dans flake.lock (nixpkgs et, le
  # cas échéant, flake-utils) et committer les deux fichiers ensemble.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/9ae611a455b90cf061d8f332b977e387bda8e1ca";
    flake-utils.url = "github:numtide/flake-utils/11707dc2f618dd54ca8739b309ec4fc024de578b";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Version de Playwright fournie par Nix (navigateurs pré-installés).
        # On force npm à installer EXACTEMENT cette version de @playwright/test
        # pour éviter tout décalage entre le driver JS et les binaires navigateur.
        playwrightVersion = pkgs.playwright-driver.version;

        # MoonScript n'est plus pris dans nixpkgs : le compilateur est le
        # sous-module backend/vendor/moonscript (tag v0.8.0), la même version
        # qu'à l'exécution dans Tarantool. Il tourne sur Lua 5.1 + lpeg,
        # argparse et luafilesystem ; son analyseur natif est compilé par le
        # Makefile dans build/.
        luaEnv = pkgs.lua5_1.withPackages (ps: [ ps.lpeg ps.argparse ps.luafilesystem ]);
        # Outils de compilation seuls (moonc + coffee), sans les navigateurs
        # Playwright (lourds). Utilisé par la CI pour vérifier que les artefacts
        # commités sont en phase avec les sources, de façon déterministe.
        buildTools = with pkgs; [ gnumake luaEnv lua5_1 nodejs_22 coffeescript git ];
      in
      {
        devShells.build = pkgs.mkShell {
          name = "tgui-build";
          packages = buildTools;
        };

        devShells.default = pkgs.mkShell {
          name = "tgui-dev";

          packages = with pkgs; [
            # Build des sources
            gnumake
            luaEnv                      # Lua 5.1 + lpeg/argparse/luafilesystem : exécute le moonc du sous-module
            nodejs_22
            coffeescript                # coffee : .coffee → .js

            # Tests navigateur
            playwright-driver.browsers  # chromium/firefox/webkit pré-installés
            shot-scraper                # captures et interactions navigateur (uvx shot-scraper)

            # Outils projet
            docker-client               # docker / docker compose (daemon = hôte)
            curl
            jq
            git
          ];

          # Utilisés par le Makefile (scripts/moonc.sh, règle build/…/native.so).
          TGUI_LUA = "${luaEnv}/bin/lua";
          TGUI_LUA_INCDIR = "${pkgs.lua5_1}/include";

          # Playwright : utiliser les navigateurs de Nix plutôt qu'un téléchargement npm.
          PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
          PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
          PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
          PLAYWRIGHT_VERSION = playwrightVersion;

          # N'afficher le bandeau qu'en shell interactif (sinon il pollue les
          # pipes de `nix develop --command ...`).
          #
          # HERMÉTISME : `nix develop` (contrairement à `nix-shell --pure`)
          # hérite de l'environnement de l'hôte, y compris LD_LIBRARY_PATH /
          # LD_PRELOAD. Sur cet hôte ils pointent vers des bibliothèques
          # compilées pour une autre glibc (alsa-lib 2.43 vs la glibc 2.42 des
          # navigateurs Playwright verrouillés), ce qui fait échouer leur
          # lancement avec « version `GLIBC_2.43' not found ». On coupe donc
          # tout héritage de recherche dynamique de bibliothèques : le shell ne
          # dépend plus que des rpath des paquets Nix.
          shellHook = ''
            unset LD_LIBRARY_PATH
            unset LD_PRELOAD
            unset LD_AUDIT
            case $- in
              *i*)
            echo "TGui dev shell"
            echo "  moonc   $(scripts/moonc.sh -v 2>/dev/null || echo 'indisponible (git submodule update --init)')"
            echo "  coffee  $(coffee --version 2>/dev/null)"
            echo "  node    $(node --version)"
            echo "  playwright (navigateurs Nix) : ${playwrightVersion}"
            echo ""
            echo "  Aligne @playwright/test sur les navigateurs Nix :"
            echo "    npm install --no-save @playwright/test@${playwrightVersion} coffeescript"
            echo ""
            echo "  Cible Docker : voir 'make up' (build via --network=host sur cet hôte)."
                ;;
            esac
          '';
        };

        # Vérification hermétique : `nix flake check` construit cette
        # dérivation en sandbox (sans réseau ni navigateur) et échoue si un
        # outil de compilation manque. C'est le filet de sécurité du shell de
        # build utilisé par la CI (`nix develop .#build`).
        checks.build-tools = pkgs.runCommand "tgui-build-tools-check" {
          nativeBuildInputs = buildTools;
        } ''
          command -v lua
          command -v coffee
          command -v node
          command -v make
          command -v gcc
          # Dépendances du moonc du sous-module (backend/vendor/moonscript).
          lua -e 'require("lpeg"); require("argparse"); require("lfs")'
          lua_ver=$(lua -v 2>&1)
          coffee_ver=$(coffee --version 2>&1)
          node_ver=$(node --version 2>&1)
          make_ver=$(make --version 2>&1 | head -1)
          echo "lua:        $lua_ver"
          echo "coffee:     $coffee_ver"
          echo "node:       $node_ver"
          echo "make:       $make_ver"
          touch "$out"
        '';
      });
}
