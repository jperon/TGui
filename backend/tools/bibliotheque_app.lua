local B = require('tools.app_builder')
local RNG = require('tools.seed_rng')
local ecole = require('tools.bibliotheque_seed_ecole')
local livres = require('tools.bibliotheque_seed_livres')
local coord = require('tools.bibliotheque_seed_coordonnees')
local DIR = '/app/backend/apps/bibliotheque'
local seed_tables
seed_tables = function(opts)
  opts = opts or { }
  local k = opts.scale or 1
  local e = ecole.generate(RNG.new(1001), k)
  local l = livres.generate(RNG.new(2002), k, e)
  local c = coord.generate(RNG.new(3003), k, e)
  local out = { }
  local _list_0 = {
    e,
    l,
    c
  }
  for _index_0 = 1, #_list_0 do
    local generated = _list_0[_index_0]
    local _list_1 = generated.tables
    for _index_1 = 1, #_list_1 do
      local t = _list_1[_index_1]
      table.insert(out, t)
    end
  end
  return out
end
local _add
_add = function(pkg, tables)
  local _list_0 = tables
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    B.add_seed(pkg, t.space, t.rows)
  end
end
local build
build = function(opts)
  opts = opts or { }
  local pkg = B.expand(B.load_structure(opts.dir or DIR))
  _add(pkg, seed_tables(opts))
  return pkg
end
local write
write = function(path, opts)
  local fio = require('fio')
  local fh = fio.open(path, {
    'O_WRONLY',
    'O_CREAT',
    'O_TRUNC'
  }, tonumber('644', 8))
  fh:write(B.emit(build(opts)))
  return fh:close()
end
return {
  build = build,
  write = write,
  seed_tables = seed_tables
}
