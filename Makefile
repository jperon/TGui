# MoonScript sources and their compiled Lua output
MOON_SRCS     := $(shell find backend tests -name '*.moon')
LUA_OUTS      := $(MOON_SRCS:.moon=.lua)

# CoffeeScript sources and their compiled JS output
COFFEE_SRCS := $(shell find frontend/src -name '*.coffee')
JS_OUTS     := $(COFFEE_SRCS:.coffee=.js)

.PHONY: all build test up down logs clean vendor

all: build

build: $(LUA_OUTS) $(JS_OUTS)

SOCKET   := /run/tarantool/sys_env/default/instance-001/tarantool.control
TESTFILE := /tmp/.tdb_test_runner.lua

test: build
	@printf "package.path='/app/?.lua;/app/backend/?.lua;'..package.path\nfor k,_ in pairs(package.loaded) do if k:match('^tests') then package.loaded[k]=nil end end\nrequire('tests.run')\n" > $(TESTFILE)
	@nlines=$$(docker logs tdb-tarantool-1 2>&1 | wc -l); \
	docker exec -i tdb-tarantool-1 tt connect $(SOCKET) -f - < $(TESTFILE) >/dev/null 2>&1; \
	sleep 1; \
	new_output=$$(docker logs tdb-tarantool-1 2>&1 | tail -n +$$((nlines + 1))); \
	echo "$$new_output" | grep -E 'assertions|RÉSULTAT'; \
	echo "$$new_output" | grep -q "RÉSULTAT: SUCCÈS" || exit 1

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
	rm -f $(LUA_OUTS) $(JS_OUTS)
