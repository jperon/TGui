{
  description = "TGui — GUI web pour Tarantool 3 (dev shell : build, tests, navigateur)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Version de Playwright fournie par Nix (navigateurs pré-installés).
        # On force npm à installer EXACTEMENT cette version de @playwright/test
        # pour éviter tout décalage entre le driver JS et les binaires navigateur.
        playwrightVersion = pkgs.playwright-driver.version;
        # Outils de compilation seuls (moonc + coffee), sans les navigateurs
        # Playwright (lourds). Utilisé par la CI pour vérifier que les artefacts
        # commités sont en phase avec les sources, de façon déterministe.
        buildTools = with pkgs; [ gnumake luaPackages.moonscript nodejs_22 coffeescript git ];
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
            luaPackages.moonscript      # moonc : .moon → .lua
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

          # Playwright : utiliser les navigateurs de Nix plutôt qu'un téléchargement npm.
          PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
          PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
          PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
          PLAYWRIGHT_VERSION = playwrightVersion;

          # N'afficher le bandeau qu'en shell interactif (sinon il pollue les
          # pipes de `nix develop --command ...`).
          shellHook = ''
            case $- in
              *i*)
            echo "TGui dev shell"
            echo "  moonc   $(moonc --version 2>/dev/null | head -1)"
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
      });
}
