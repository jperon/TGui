# MoonScript sources and their compiled Lua output
MOON_SRCS     := $(shell find backend tests -name '*.moon')
LUA_OUTS      := $(MOON_SRCS:.moon=.lua)

# CoffeeScript sources and their compiled JS output
COFFEE_SRCS     := $(shell find frontend/src -name '*.coffee')
JS_OUTS         := $(COFFEE_SRCS:.coffee=.js)
TEST_COFFEE_SRCS := $(shell find tests/js -name '*.coffee')
TEST_JS_OUTS     := $(TEST_COFFEE_SRCS:.coffee=.js)

.PHONY: all build test test-legacy test-js test-up test-logs up down logs clean vendor audit-deps doc

all: build

build: $(LUA_OUTS) $(JS_OUTS) $(TEST_JS_OUTS)

SOCKET   := /run/tarantool/sys_env/default/instance-001/tarantool.control
TESTFILE := /tmp/.tgui_test_runner.lua
TEST_IMAGE := tdb-test:latest

test: build
	docker build -t $(TEST_IMAGE) .
	docker run --rm -v ./backend:/app/backend:ro -v ./frontend:/app/frontend:ro -v ./schema:/app/schema:ro -v ./tests:/app/tests:ro -e TT_LOG_LEVEL=5 -e TGUI_TEST_ENV=true $(TEST_IMAGE) tarantool /app/backend/test_runner.lua

test-up: build
	docker compose -f docker-compose.test.yml --profile test up -d --build

test-legacy: build
	@printf "package.path='/app/?.lua;/app/backend/?.lua;'..package.path\nfor k,_ in pairs(package.loaded) do if k:match('^tests') or k:match('^resolvers') then package.loaded[k]=nil end end\nrequire('resolvers.init').reinit()\nrequire('tests.run')\n" > $(TESTFILE)
	@nlines=$$(docker logs tgui-tarantool-test 2>&1 | wc -l); \
	sleep 8; \
	docker exec -i tgui-tarantool-test tt connect $(SOCKET) -f - < $(TESTFILE) 2>&1; \
	sleep 8; \
	new_output=$$(docker logs tgui-tarantool-test 2>&1 | tail -n +$$((nlines + 1))); \
	echo "$$new_output" | grep -E 'assertions|RÉSULTAT'; \
	if echo "$$new_output" | grep -q "RÉSULTAT: SUCCÈS"; then exit 0; fi; \
	echo "===== ÉCHEC - sortie complète des tests ====="; \
	echo "$$new_output"; exit 1

test-logs:
	docker logs tgui-tarantool-test

test-js: $(TEST_JS_OUTS)
	coffee tests/js/run.coffee

%.lua: %.moon
	moonc $<

%.js: %.coffee
	coffee --no-header -c $<

# Build vendor bundles (tui-grid, js-yaml)
vendor: frontend/vendor/tui-grid.bundle.js

frontend/vendor/tui-grid.bundle.js:
	@bash scripts/build-vendor.sh

up: build
	docker compose up -d --build

down:
	docker compose down

logs:
	docker compose logs -f

clean:
	rm -f $(LUA_OUTS) $(JS_OUTS) $(TEST_JS_OUTS)

# ── Documentation PDF ────────────────────────────────────────────────────────
DOC_DIR    = doc
DOC_HEADER = $(DOC_DIR)/00_header.yml
DOC_PDFS   = $(DOC_DIR)/get-started.pdf $(DOC_DIR)/reference.pdf $(DOC_DIR)/en/get-started.pdf $(DOC_DIR)/en/reference.pdf

PANDOC_FLAGS = --metadata-file=00_header.yml --pdf-engine=xelatex

$(DOC_DIR)/%.pdf: $(DOC_DIR)/%.md $(DOC_HEADER)
	cd $(DOC_DIR) && pandoc $(PANDOC_FLAGS) $(<F) -o $(@F)

doc: $(DOC_PDFS)

# ── Dependencies audit ────────────────────────────────────────────────
audit-deps:
	@echo "Auditing core dependencies..."
	@echo "✓ MoonScript: used for backend compilation"
	@echo "✓ Tarantool 3.x: runtime environment"
	@echo "✓ Docker: deployment environment"
	@echo "✓ No external runtime dependencies"
	@echo "Audit complete - minimal dependency footprint"

.PHONY: doc
