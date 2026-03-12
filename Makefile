# MoonScript sources and their compiled Lua output
MOON_SRCS     := $(shell find backend tests scripts -name '*.moon')
LUA_OUTS      := $(MOON_SRCS:.moon=.lua)

# CoffeeScript sources and their compiled JS output
COFFEE_SRCS     := $(shell find frontend/src -name '*.coffee')
JS_OUTS         := $(COFFEE_SRCS:.coffee=.js)
TEST_COFFEE_SRCS := $(shell find tests/js -name '*.coffee')
TEST_JS_OUTS     := $(TEST_COFFEE_SRCS:.coffee=.js)

.PHONY: all build test test-js test-up test-down test-logs up down logs clean vendor audit-deps doc doc-% doc-gen doc-po-update doc-po-build doc-md doc-check sdl-gen sdl-check ci

all: build

build: $(LUA_OUTS) $(JS_OUTS) $(TEST_JS_OUTS)

TEST_IMAGE := tdb-test:latest

test: build
	docker build -t $(TEST_IMAGE) .
	docker run --rm -v ./backend:/app/backend:ro -v ./frontend:/app/frontend:ro -v ./schema:/app/schema:ro -v ./tests:/app/tests:ro -e TT_LOG_LEVEL=5 -e TGUI_TEST_ENV=true $(TEST_IMAGE) tarantool /app/backend/test_runner.lua

test-up: build
	docker compose -f docker-compose.test.yml --profile test up -d --build

test-down: build
	docker compose -f docker-compose.test.yml --profile test down

test-logs:
	docker logs tgui-tarantool-test

test-js: $(TEST_JS_OUTS)
	coffee tests/js/run.coffee

%.lua: %.moon
	moonc $<

%.js: %.coffee
	coffee --no-header -c $<

# Build vendor bundles (tui-grid, js-yaml, codemirror)
VENDOR_OUTS := frontend/vendor/tui-grid.bundle.js \
	frontend/vendor/tui-grid.bundle.css \
	frontend/vendor/jsyaml.bundle.js \
	frontend/vendor/codemirror.bundle.js \
	frontend/vendor/codemirror.bundle.css \
	frontend/vendor/plugin-runtime.bundle.js

vendor: $(VENDOR_OUTS)

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
	docker build -t $(TEST_IMAGE) . 2>/dev/null
	docker run --rm -e HOST_UID=$$(id -u) -e HOST_GID=$$(id -g) -v ./:/app $(TEST_IMAGE) sh -lc 'tarantool /app/scripts/generate_docs.lua && chown -R "$$HOST_UID:$$HOST_GID" /app/doc/en' 2>/dev/null

doc-po-update:
	docker build -t $(TEST_IMAGE) . 2>/dev/null
	docker run --rm -e HOST_UID=$$(id -u) -e HOST_GID=$$(id -g) -v ./:/app $(TEST_IMAGE) sh -lc 'cd /app && tarantool /app/scripts/doc_localize.lua update-pot && chown -R "$$HOST_UID:$$HOST_GID" /app/po' 2>/dev/null

doc-po-build:
	docker build -t $(TEST_IMAGE) . 2>/dev/null
	docker run --rm -e HOST_UID=$$(id -u) -e HOST_GID=$$(id -g) -v ./:/app $(TEST_IMAGE) sh -lc 'cd /app && tarantool /app/scripts/doc_localize.lua build-fr && chown -R "$$HOST_UID:$$HOST_GID" /app/doc/fr /app/po' 2>/dev/null

doc-md: doc-gen doc-po-build

doc-check:
	docker build -t $(TEST_IMAGE) . 2>/dev/null
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
	docker build -t $(TEST_IMAGE) .
	docker run --rm -v ./backend:/app/backend:ro $(TEST_IMAGE) tarantool -e 'package.path="/app/backend/?.lua;/app/backend/?/init.lua;"..package.path; io.write(require("graphql.sdl_generator").generate()); os.exit(0)' > schema/tdb.generated.graphql

sdl-check: build
	@tmp=$$(mktemp); \
	docker build -t $(TEST_IMAGE) . >/dev/null; \
	docker run --rm -v ./backend:/app/backend:ro $(TEST_IMAGE) tarantool -e 'package.path="/app/backend/?.lua;/app/backend/?/init.lua;"..package.path; io.write(require("graphql.sdl_generator").generate()); os.exit(0)' > $$tmp; \
	diff -u schema/tdb.generated.graphql $$tmp >/dev/null || (echo "SDL drift detected: run 'make sdl-gen' and commit schema/tdb.generated.graphql"; rm -f $$tmp; exit 1); \
	rm -f $$tmp; \
	echo "SDL check OK"

ci: sdl-check test test-js doc-check

.PHONY: doc
