-- core/plugin_compile.moon
-- Server-side compilation of a custom widget definition's script (spec §7).
--
-- `moonscript` is transpiled to Lua with moonscript.base.to_lua — the same
-- compiler the trigger formulas use — and the resulting chunk is cached in the
-- `compiled` column of _tdb_widget_plugins. A parse error refuses the save with
-- a message naming the offending line; the Lua produced by moonc is valid in
-- Lua 5.1 (Tarantool) as well as Lua 5.4 (browser).
--
-- `lua` is stored as written and never syntax-checked here: the widget runs in
-- the browser under wasmoon (Lua 5.4), whose syntax is not LuaJIT's (Lua 5.1) —
-- `//`, `&`, `|`, `~`, `<<`, `>>`, `<const>`, `goto` are valid there and would
-- be refused for nothing by `loadstring`. A syntax error is reported inside the
-- widget by wasmoon, with the offending line (`[string "..."]:N:`).
--
-- Other languages (javascript, coffeescript) are compiled by the browser and
-- store no compiled code.
--
-- The source stays the reference for export and fingerprints (§5): `compiled`
-- is only a cache, recomputed at every save (for `lua` it is the source).
--
-- Depends on: moonscript.base (vendored MoonScript 0.8.0).
-- Used by: resolvers/widget_plugin_resolvers.moon, core/app_apply.moon,
-- resolvers/export_resolvers.moon (snapshot import).

MAX_COMPILED_LEN = 400000

-- Line number reported by MoonScript (`failed to parse at line 3, column 5`).
line_of = (err) ->
  s = tostring err
  line = s\match 'line (%d+)'
  line = s\match ':(%d+):' unless line
  line

location_suffix = (err) ->
  line = line_of err
  if line then " (ligne #{line})" else ''

compile_error = (language, err) ->
  error "WidgetPlugin script: #{language} invalide#{location_suffix err} : #{tostring err}", 0

-- Lua: no server-side syntax check (see the header). The source is executed as
-- written by wasmoon in the browser; storing it verbatim is the cache.
compile_lua = (code) ->
  code

-- MoonScript: transpile to Lua now, so the browser only ever runs Lua and a
-- parse error is reported while saving (with its line), never inside a page.
compile_moonscript = (code) ->
  ok, moon = pcall require, 'moonscript.base'
  unless ok
    error "WidgetPlugin script: compilateur MoonScript indisponible : #{tostring moon}", 0
  lua, err = moon.to_lua code
  unless lua and type(lua) == 'string'
    compile_error 'MoonScript', err or 'compilation impossible'
  error "WidgetPlugin script: code compilé trop long (#{#lua} > #{MAX_COMPILED_LEN})" if #lua > MAX_COMPILED_LEN
  lua

-- Compiled text to cache for `language`, or '' for a browser-compiled language.
-- MoonScript raises with a field-precise message: the editor shows it next to
-- the script. Lua never raises here: its errors surface in the widget.
compile_script = (language, code) ->
  source = tostring code or ''
  switch string.lower tostring(language or '')
    when 'lua'
      compile_lua source
    when 'moonscript'
      compile_moonscript source
    else
      ''

{ :compile_script, :MAX_COMPILED_LEN }
