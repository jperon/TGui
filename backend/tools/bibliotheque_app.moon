-- tools/bibliotheque_app.moon
-- Assembleur de l'application « Bibliothèque » : structure YAML + seeds.
B = require 'tools.app_builder'
RNG = require 'tools.seed_rng'
ecole = require 'tools.bibliotheque_seed_ecole'
livres = require 'tools.bibliotheque_seed_livres'
coord = require 'tools.bibliotheque_seed_coordonnees'

DIR = '/app/backend/apps/bibliotheque'

-- Grain des seeds, indépendant de la structure : école, puis livres, puis
-- coordonnées (les deux derniers consomment le résultat de l'école).
seed_tables = (opts) ->
  opts or= {}
  k = opts.scale or 1
  e = ecole.generate RNG.new(1001), k
  l = livres.generate RNG.new(2002), k, e
  c = coord.generate RNG.new(3003), k, e
  out = {}
  for generated in *{ e, l, c }
    for t in *generated.tables
      table.insert out, t
  out

_add = (pkg, tables) ->
  B.add_seed pkg, t.space, t.rows for t in *tables

build = (opts) ->
  opts or= {}
  pkg = B.expand B.load_structure opts.dir or DIR
  _add pkg, seed_tables opts
  pkg

write = (path, opts) ->
  fio = require 'fio'
  fh = fio.open path, { 'O_WRONLY', 'O_CREAT', 'O_TRUNC' }, tonumber('644', 8)
  fh\write B.emit build opts
  fh\close!

{ :build, :write, :seed_tables }
