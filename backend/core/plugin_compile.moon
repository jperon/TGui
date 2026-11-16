-- core/plugin_compile.moon
-- Compilation of a custom widget definition's script (spec widgets
-- personnalisés §7). `lua` is syntax-checked with loadstring and stored as
-- written; `moonscript` is transpiled to Lua with moonscript.base.to_lua — the
-- same compiler the trigger formulas use — and the resulting chunk is cached in
-- the `compiled` column of _tdb_widget_plugins. Other languages (javascript,
-- coffeescript) are compiled by the browser and store no compiled code.
--
-- The source stays the reference for export and fingerprints (§5): `compiled`
-- is only a cache, recomputed at every save. A compilation error refuses the
-- save with a message naming the offending line.
--
-- Depends on: moonscript.base (vendored MoonScript 0.8.0).
-- Used by: resolvers/widget_plugin_resolvers.moon, core/app_apply.moon,
-- resolvers/export_resolvers.moon (snapshot import).

MAX_COMPILED_LEN = 400000

-- Line number reported by Lua (`[string "..."]:3:`) or MoonScript
-- (`failed to parse at line 3, column 5`).
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

-- Lua: only the syntax is checked; the source itself is executed in the
-- browser by wasmoon (Lua 5.4), so no chunk is cached.
compile_lua = (code) ->
  fn, err = loadstring code
  compile_error 'Lua', err unless fn
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
-- Raises with a field-precise message: the editor shows it next to the script.
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
