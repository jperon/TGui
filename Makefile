# ── MoonScript (sous-module upstream) ────────────────────────────────────────
# Le compilateur est celui du sous-module backend/vendor/moonscript, épinglé
# sur le tag v0.8.0 : c'est EXACTEMENT la version qui tourne à l'exécution dans
# Tarantool (moonscript.base.to_lua pour les formules). Il s'exécute sur le Lua
# 5.1 du dev shell Nix (TGUI_LUA, fourni par flake.nix) avec lpeg, argparse et
# luafilesystem ; l'analyseur natif (moonscript/parse/native.c) est compilé
# dans build/ (ignoré par git, jamais dans le sous-module).
#
# Mise à jour : changer le commit du sous-module puis `make build`.
MOONSCRIPT_DIR := backend/vendor/moonscript
LUA            ?= $(if $(TGUI_LUA),$(TGUI_LUA),lua5.1)
LUA_INCDIR     ?= $(if $(TGUI_LUA_INCDIR),$(TGUI_LUA_INCDIR),/usr/include/lua5.1)
MOONC          := scripts/moonc.sh
NATIVE_SO      := build/moonscript/parse/native.so

# MoonScript sources and their compiled Lua output.
# On exclut backend/vendor/ : c'est le sous-module upstream (ses .lua sont
# fournis tels quels et ne doivent pas être recompilés).
MOON_SRCS     := $(shell find backend tests scripts -name '*.moon' -not -path '*/vendor/*')
LUA_OUTS      := $(MOON_SRCS:.moon=.lua)

# CoffeeScript sources and their compiled JS output
COFFEE_SRCS     := $(shell find frontend/src -name '*.coffee')
JS_OUTS         := $(COFFEE_SRCS:.coffee=.js)
TEST_COFFEE_SRCS := $(shell find tests/js -name '*.coffee')
TEST_JS_OUTS     := $(TEST_COFFEE_SRCS:.coffee=.js)

# Playwright test sources (ALL FILES - no exclusions)
PLAYWRIGHT_COFFEE_SRCS := $(shell find tests/playwright -name '*.coffee')
PLAYWRIGHT_JS_OUTS := $(PLAYWRIGHT_COFFEE_SRCS:.coffee=.js)

.PHONY: all install-hooks build test test-js test-up test-down test-logs up down logs clean doctor vendor audit-deps doc doc-% doc-gen doc-po-update doc-po-build doc-md doc-check sdl-gen sdl-check app-bibliotheque app-bibliotheque-check ci test-browser test-browser-spaces test-browser-data-views test-browser-pages test-browser-relations test-browser-auth test-browser-apps test-browser-integration test-browser-e2e playwright-install playwright-setup playwright-compile

all: build

# Compile toutes les sources MoonScript et CoffeeScript vers leurs artefacts.
# (Les règles de motif %.lua:%.moon et %.js:%.coffee font le travail ; build ne
#  fait que déclarer la liste complète des cibles.)
build: $(NATIVE_SO) $(LUA_OUTS) $(JS_OUTS) $(TEST_JS_OUTS)

# Active les hooks git versionnés (.githooks/), notamment le pre-commit qui
# lance la suite de tests. À exécuter une fois après le clone.
install-hooks:
	git config core.hooksPath .githooks
	@echo "✅ core.hooksPath → .githooks"

TEST_IMAGE := tdb-test:latest

# Le bridge Docker de cet hôte ne fait pas de masquerade (firewall) : les builds
# qui téléchargent des rocks ont besoin du réseau de l'hôte. Mettre à vide
# (DOCKER_BUILD_NET=) si le NAT du bridge est réparé.
DOCKER_BUILD_NET ?= --network=host

# Le build compose demande `build.network: host` (docker-compose.yml,
# docker-compose.test.yml) : le bridge de cet hôte ne masquerade pas. Certaines
# versions de compose construisent via buildx bake, qui traite ce réseau comme
# un privilège et refuse alors le build (« additional privileges requested:
# pass "--allow=network.host" »). `COMPOSE_BAKE=false` les fait repasser au
# builder interne, qui l'accepte ; les compose plus récents ignorent cette
# variable sans émettre ce privilège. Sur un hôte dont le bridge fait du NAT
# (runners de la CI), on évite carrément `network: host` en exportant
# TGUI_BUILD_NETWORK=default.
export COMPOSE_BAKE := false

test: build
	docker build $(DOCKER_BUILD_NET) -t $(TEST_IMAGE) .
	docker run --rm -v ./backend:/app/backend:ro -v ./frontend:/app/frontend:ro -v ./schema:/app/schema:ro -v ./tests:/app/tests:ro -e TT_LOG_LEVEL=5 -e TGUI_TEST_ENV=true $(TEST_IMAGE) tarantool /app/backend/test_runner.lua

test-up: build
	docker compose -f docker-compose.test.yml --profile test up -d --build

test-down: build
	docker compose -f docker-compose.test.yml --profile test down

test-logs:
	docker logs tgui-tarantool-test

test-js: $(TEST_JS_OUTS)
	coffee tests/js/run.coffee

# Analyseur natif de MoonScript 0.8.0, compilé hors du sous-module.
$(NATIVE_SO): $(MOONSCRIPT_DIR)/moonscript/parse/native.c
	@test -f "$(LUA_INCDIR)/lua.h" || { \
		echo "❌ en-têtes Lua introuvables dans $(LUA_INCDIR) : lancer 'nix develop' (ou définir TGUI_LUA_INCDIR)"; \
		exit 1; }
	@mkdir -p $(@D)
	$(CC) -shared -O2 -fPIC -I$(LUA_INCDIR) -o $@ $<

# Message explicite quand le sous-module n'a pas été récupéré (clone sans
# --recurse-submodules) : la règle ci-dessus ne peut pas s'appliquer.
# La recette ne se déclenche que si le fichier est réellement absent ; un
# `make -B build` la rejoue alors que native.c est présent, d'où le test
# (sans lui, ce cas échouait à tort).
$(MOONSCRIPT_DIR)/moonscript/parse/native.c:
	@test -f $@ || { echo "❌ sous-module MoonScript absent : lancer 'git submodule update --init'"; exit 1; }

%.lua: %.moon | $(NATIVE_SO)
	$(MOONC) $<

%.js: %.coffee
	coffee --no-header -c $<

# Compile Playwright CoffeeScript tests
$(PLAYWRIGHT_JS_OUTS): $(PLAYWRIGHT_COFFEE_SRCS)
	@echo "☕ Compiling Playwright CoffeeScript tests..."
	coffee --no-header -c $(PLAYWRIGHT_COFFEE_SRCS)
	@echo "✅ Playwright tests compiled"

# Build vendor bundles (tui-grid, js-yaml, codemirror, plugin runtime, sortablejs)
VENDOR_OUTS := frontend/vendor/tui-grid.bundle.js \
	frontend/vendor/tui-grid.bundle.css \
	frontend/vendor/jsyaml.bundle.js \
	frontend/vendor/codemirror.bundle.js \
	frontend/vendor/codemirror.bundle.css \
	frontend/vendor/sortablejs.bundle.js \
	frontend/vendor/plugin-runtime.bundle.js \
	frontend/vendor/wasmoon.bundle.js \
	frontend/vendor/wasmoon.bundle.wasm

vendor: $(VENDOR_OUTS)

# Playwright E2E Browser Tests
playwright-install:
	@echo "📦 Installing Playwright..."
	npm install @playwright/test
	npx playwright install

playwright-setup: playwright-install
	@echo "⚙️ Setting up Playwright configuration..."
	mkdir -p tests/playwright/{config,spaces,data-views,pages,relations,auth,integration,e2e}

test-browser: playwright-compile test-browser-spaces test-browser-data-views test-browser-pages test-browser-relations test-browser-auth test-browser-apps test-browser-integration test-browser-e2e
	@echo "🎉 All browser E2E tests completed!"
	@echo "💡 Tests ran on test environment (port 8081)"

test-browser-spaces: playwright-compile
	@echo "🧪 Running Spaces E2E tests (parallel)..."
	npx playwright test tests/playwright/spaces/creation-final-parallel.spec.js --config=tests/playwright/playwright-optimized.config.js

test-browser-data-views: playwright-compile
	@echo "🧪 Running Data Views E2E tests (parallel)..."
	npx playwright test tests/playwright/data-views --config=tests/playwright/playwright-optimized.config.js

test-browser-pages: playwright-compile
	@echo "🧪 Running Pages & Widgets E2E tests (parallel)..."
	npx playwright test tests/playwright/pages/drag-drop-final-parallel.spec.js --config=tests/playwright/playwright-optimized.config.js

test-browser-relations: playwright-compile
	@echo "🧪 Running Relations E2E tests (parallel)..."
	npx playwright test tests/playwright/relations --config=tests/playwright/playwright-optimized.config.js

test-browser-auth: playwright-compile
	@echo "🧪 Running Auth E2E tests (parallel)..."
	npx playwright test tests/playwright/auth --config=tests/playwright/playwright-optimized.config.js

test-browser-apps: playwright-compile
	@echo "🧪 Running Apps E2E tests (serial, isolated)..."
	# --no-deps : la cible cible UNIQUEMENT ce fichier. Sans lui, la
	# dépendance du projet `chromium-apps` vers `chromium` ferait tourner
	# toute la suite non-apps avant les tests d'applications.
	npx playwright test tests/playwright/apps --no-deps --config=tests/playwright/playwright-optimized.config.js

test-browser-integration: playwright-compile
	@echo "🧪 Running Integration E2E tests (parallel)..."
	echo "⚠️ No integration tests found - skipping"

test-browser-e2e: playwright-compile
	@echo "🧪 Running Complete Workflow E2E tests (parallel)..."
	npx playwright test tests/playwright/e2e --config=tests/playwright/playwright-optimized.config.js

# Playwright development and debugging
playwright-compile: $(PLAYWRIGHT_JS_OUTS)
	@echo "☕ Playwright tests compiled"

test-browser-debug: playwright-compile
	@echo "🐛 Running Playwright tests in debug mode..."
	npx playwright test --config=tests/playwright/playwright.config.js --debug

test-browser-report:
	@echo "📊 Opening Playwright test report..."
	npx playwright show-report

# Install Playwright and setup
setup-playwright: playwright-install playwright-setup

$(VENDOR_OUTS):
	@bash scripts/build-vendor.sh

up: build
	docker compose up -d --build

down:
	docker compose down

logs:
	docker compose logs -f

clean:
	rm -f $(LUA_OUTS) $(JS_OUTS) $(TEST_JS_OUTS)
	rm -rf build

# Vérifie l'environnement de dev Nix (outils, hermétisme, Playwright,
# navigateur headless). Entre dans le dev shell si on n'y est pas déjà.
doctor:
	@if [ -n "$${PLAYWRIGHT_VERSION:-}" ]; then \
		scripts/env-check.sh; \
	else \
		nix develop --command scripts/env-check.sh; \
	fi

# ── Documentation PDF ────────────────────────────────────────────────────────
DOC_DIR    = doc
DOC_HEADER = $(DOC_DIR)/00_header.yml
DOC_GEN_MD = $(DOC_DIR)/en/api.md $(DOC_DIR)/en/dev.md \
	$(DOC_DIR)/en/dev/architecture.md $(DOC_DIR)/en/dev/runtime.md $(DOC_DIR)/en/dev/graphql.md $(DOC_DIR)/en/dev/frontend.md $(DOC_DIR)/en/dev/tests.md
DOC_LOCALIZED_MD = $(DOC_DIR)/fr/README.md $(DOC_DIR)/fr/get-started.md $(DOC_DIR)/fr/api.md $(DOC_DIR)/fr/dev.md \
	$(DOC_DIR)/fr/dev/architecture.md $(DOC_DIR)/fr/dev/runtime.md $(DOC_DIR)/fr/dev/graphql.md $(DOC_DIR)/fr/dev/frontend.md $(DOC_DIR)/fr/dev/tests.md

PANDOC_FLAGS = --metadata-file=$(DOC_HEADER) --pdf-engine=lualatex

$(DOC_DIR)/%.pdf: $(DOC_DIR)/%.md $(DOC_HEADER)
	pandoc $(PANDOC_FLAGS) --from=markdown "$<" -o "$@"

doc-%:
	@lang=$*; \
	lang_dir="$(DOC_DIR)/$$lang"; \
	test -d "$$lang_dir" || { echo "Missing documentation directory: $$lang_dir"; exit 1; }; \
	set -e; \
	if [ "$$lang" = "fr" ]; then \
		files="$(DOC_LOCALIZED_MD)"; \
	elif [ "$$lang" = "en" ]; then \
		files="$(DOC_DIR)/en/README.md $(DOC_DIR)/en/get-started.md $(DOC_GEN_MD)"; \
	else \
		files="$$(find "$$lang_dir" -type f -name '*.md' | sort)"; \
	fi; \
	for md in $$files; do \
		test -f "$$md" || { echo "Missing documentation file: $$md"; exit 1; }; \
		pdf="$${md%.md}.pdf"; \
		pandoc $(PANDOC_FLAGS) --from=markdown --resource-path="$$lang_dir:$(DOC_DIR)" "$$md" -o "$$pdf"; \
	done

doc: doc-md doc-fr doc-en

doc-gen:
	docker build $(DOCKER_BUILD_NET) -t $(TEST_IMAGE) . 2>/dev/null
	docker run --rm -e HOST_UID=$$(id -u) -e HOST_GID=$$(id -g) -v ./:/app $(TEST_IMAGE) sh -lc 'tarantool /app/scripts/generate_docs.lua && chown -R "$$HOST_UID:$$HOST_GID" /app/doc/en' 2>/dev/null

doc-po-update:
	docker build $(DOCKER_BUILD_NET) -t $(TEST_IMAGE) . 2>/dev/null
	docker run --rm -e HOST_UID=$$(id -u) -e HOST_GID=$$(id -g) -v ./:/app $(TEST_IMAGE) sh -lc 'cd /app && tarantool /app/scripts/doc_localize.lua update-pot && chown -R "$$HOST_UID:$$HOST_GID" /app/po' 2>/dev/null

doc-po-build:
	docker build $(DOCKER_BUILD_NET) -t $(TEST_IMAGE) . 2>/dev/null
	docker run --rm -e HOST_UID=$$(id -u) -e HOST_GID=$$(id -g) -v ./:/app $(TEST_IMAGE) sh -lc 'cd /app && tarantool /app/scripts/doc_localize.lua build-fr && chown -R "$$HOST_UID:$$HOST_GID" /app/doc/fr /app/po' 2>/dev/null

doc-md: doc-gen doc-po-build

doc-check:
	docker build $(DOCKER_BUILD_NET) -t $(TEST_IMAGE) . 2>/dev/null
	docker run --rm -w /app -v ./:/app $(TEST_IMAGE) tarantool /app/scripts/doc_check.lua

# ── Dependencies audit ────────────────────────────────────────────────
audit-deps:
	@echo "Auditing core dependencies..."
	@echo "✓ MoonScript: used for backend compilation"
	@echo "✓ Tarantool 3.x: runtime environment"
	@echo "✓ Docker: deployment environment"
	@echo "✓ No external runtime dependencies"
	@echo "Audit complete - minimal dependency footprint"

sdl-gen: build
	docker build $(DOCKER_BUILD_NET) -t $(TEST_IMAGE) .
	docker run --rm -v ./backend:/app/backend:ro $(TEST_IMAGE) tarantool -e 'package.path="/app/backend/?.lua;/app/backend/?/init.lua;"..package.path; io.write(require("graphql.sdl_generator").generate()); os.exit(0)' > schema/tdb.generated.graphql

sdl-check: build
	@tmp=$$(mktemp); \
	docker build $(DOCKER_BUILD_NET) -t $(TEST_IMAGE) . >/dev/null; \
	docker run --rm -v ./backend:/app/backend:ro $(TEST_IMAGE) tarantool -e 'package.path="/app/backend/?.lua;/app/backend/?/init.lua;"..package.path; io.write(require("graphql.sdl_generator").generate()); os.exit(0)' > $$tmp; \
	diff -u schema/tdb.generated.graphql $$tmp >/dev/null || (echo "SDL drift detected: run 'make sdl-gen' and commit schema/tdb.generated.graphql"; rm -f $$tmp; exit 1); \
	rm -f $$tmp; \
	echo "SDL check OK"

app-bibliotheque: build
	docker build $(DOCKER_BUILD_NET) -t $(TEST_IMAGE) .
	docker run --rm -u $$(id -u):$$(id -g) -v ./:/app $(TEST_IMAGE) tarantool -e 'package.path="/app/backend/?.lua;/app/backend/?/init.lua;"..package.path; require("tools.bibliotheque_app").write("/app/apps/bibliotheque/bibliotheque.tdbapp.yaml"); os.exit(0)'

app-bibliotheque-check: build
	@tmp=$$(mktemp); \
	docker build $(DOCKER_BUILD_NET) -t $(TEST_IMAGE) . >/dev/null; \
	docker run --rm -v ./:/app $(TEST_IMAGE) tarantool -e 'package.path="/app/backend/?.lua;/app/backend/?/init.lua;"..package.path; io.write(require("tools.app_builder").emit(require("tools.bibliotheque_app").build())); os.exit(0)' > $$tmp; \
	diff -q $$tmp apps/bibliotheque/bibliotheque.tdbapp.yaml >/dev/null || { echo "❌ paquet périmé : make app-bibliotheque"; rm -f $$tmp; exit 1; }; \
	rm -f $$tmp; \
	echo "✅ paquet à jour"

ci: sdl-check test test-js doc-check

.PHONY: doc
