# MoonScript sources and their compiled Lua output
MOON_SRCS := $(shell find backend -name '*.moon')
LUA_OUTS  := $(MOON_SRCS:.moon=.lua)

# CoffeeScript sources and their compiled JS output
COFFEE_SRCS := $(shell find frontend/src -name '*.coffee')
JS_OUTS     := $(COFFEE_SRCS:.coffee=.js)

.PHONY: all build up down logs clean vendor

all: build

build: $(LUA_OUTS) $(JS_OUTS)

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
