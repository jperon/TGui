-- tests/test_bibliotheque_vues_pages.moon
-- T16b — vues de données et pages de l'application Bibliothèque.
-- Vérifie le paquet construit (8 vues, 4 pages, version 1.1.0), l'état installé
-- par les fixtures, l'exécution des 8 vues sur le seed, et la validité des pages.

R = require 'tests.runner'
json = require 'json'
yaml = require 'yaml'
spaces = require 'core.spaces'
auth = require 'core.auth'
apply = require 'core.app_apply'
data_views = require 'core.data_views'
executor = require 'core.data_views_executor'
fiber = require 'fiber'

APP_ID = 'org.tgui.bibliotheque'

EXPECTED_VIEWS = {
  'Emprunts en cours'
  'Exemplaires disponibles'
  'Exemplaires prêtés'
  'Livres sans exemplaire'
  'Livres les plus empruntés'
  'Emprunts par année'
  'Livres par genre'
  'Effectifs par classe'
}

EXPECTED_PAGES = {
  'Prêts et retours'
  'Catalogue'
  'Lecteurs et classes'
  'Tableau de bord'
}

admin = auth.get_user_by_username 'admin'
CTX = { user_id: admin and admin.id }

pkg_mod = nil
pkg = ->
  pkg_mod or= require('tools.bibliotheque_app').build!
  pkg_mod

items_of_type = (t) ->
  [it for it in *pkg!.items when it.type == t]

-- ── état installé ────────────────────────────────────────────────────────────

data_view_rows = ->
  out = {}
  for t in *box.space._tdb_data_views\select {}
    out[t[2]] = { id: t[1], name: t[2], description: t[3], sourceSpace: t[4], config: t[5] }
  out

page_rows = ->
  out = {}
  for t in *box.space._tdb_custom_views\select {}
    out[t[2]] = { id: t[1], name: t[2], description: t[3], yaml: t[4] }
  out

exec_view = (name) ->
  v = data_views.get_view_by_name name
  error "vue absente: #{name}" unless v
  -- Rend la main : l'évaluation des formules de filtre/regroupement sur le seed
  -- consomme beaucoup d'instructions sans écriture et épuiserait la tranche de
  -- fibre de l'instance de test (même précaution que T9b).
  fiber.yield!
  executor.execute_view v.sourceSpace, v.config, {}

-- ── validation des pages ─────────────────────────────────────────────────────

space_fields = (name) ->
  sp = spaces.get_space_by_name name
  return nil unless sp
  m = {}
  m[f.name] = true for f in *spaces.list_fields sp.id
  m

view_columns = (name) ->
  v = data_views.get_view_by_name name
  return nil unless v
  cfg = {}
  ok, dec = pcall json.decode, v.config
  cfg = dec if ok and type(dec) == 'table'
  cols = {}
  for c in *(cfg.columns or {})
    if type(c) == 'string'
      cols[c] = true
    elseif type(c) == 'table' and c.field
      cols[c.as or c.field] = true
  for f in *(cfg.groupBy or {})
    cols[f] = true
  for a in *(cfg.aggregates or {})
    alias = a.as or (if a.field then "#{a.fn}_#{a.field}" else a.fn)
    cols[alias] = true
  cols

ref_fields = (name) ->
  f = space_fields name
  f or view_columns name

walk_widgets = (node, out) ->
  return unless type(node) == 'table'
  if node.widget
    table.insert out, node.widget
    return
  if node.layout
    walk_widgets node.layout, out
    return
  for c in *(node.children or {})
    walk_widgets c, out

validate_page = (name) ->
  t = box.space._tdb_custom_views\select {}
  yml = nil
  for row in *t
    yml = row[4] if row[2] == name
  unless yml
    R.ok false, "page #{name}: absente de _tdb_custom_views"
    return
  ok, doc = pcall yaml.decode, yml
  R.ok ok, "page #{name}: YAML invalide (#{doc})"
  return unless ok
  R.ok doc.layout, "page #{name}: layout absent"
  return unless doc.layout
  widgets = {}
  walk_widgets doc.layout, widgets
  R.ok #widgets > 0, "page #{name}: aucun widget"
  seen = {}
  for w in *widgets
    ref = w.space
    if not ref
      R.ok false, "page #{name}: widget sans 'space'"
    else
      fields = ref_fields ref
      if not fields
        R.ok false, "page #{name}: '#{ref}' ne référence ni espace ni vue"
        fields = {}
      for col in *(w.columns or {})
        R.ok fields[col], "page #{name}: colonne '#{col}' inconnue dans '#{ref}'"
      for g in *(w.groupBy or {})
        R.ok fields[g], "page #{name}: groupBy '#{g}' inconnu dans '#{ref}'"
      dep = w.depends_on
      if dep
        src = seen[dep.widget]
        R.ok src, "page #{name}: depends_on '#{dep.widget}' non défini plus haut"
        if dep.field
          R.ok fields[dep.field], "page #{name}: field '#{dep.field}' inconnu dans '#{ref}'"
        if src and dep.from_field
          srcfields = ref_fields(src.space) or {}
          R.ok srcfields[dep.from_field], "page #{name}: from_field '#{dep.from_field}' inconnu dans '#{src.space}'"
    seen[w.id] = w if w.id

-- ── tests ────────────────────────────────────────────────────────────────────

R.describe "T16b — paquet Bibliothèque (vues et pages)", ->

  R.it "a 8 vues de données et 4 pages, version 1.1.0", ->
    R.eq pkg!.app.version, '1.1.0', 'version'
    dv_items = items_of_type 'dataview'
    pg_items = items_of_type 'page'
    R.eq #dv_items, 8, 'items dataview'
    R.eq #pg_items, 4, 'items page'
    R.eq json.encode([it.content.name for it in *dv_items]), json.encode(EXPECTED_VIEWS), 'noms des vues'
    R.eq json.encode([it.content.name for it in *pg_items]), json.encode(EXPECTED_PAGES), 'noms des pages'

R.describe "T16b — état installé", ->

  R.it "applies the current package (idempotent on a fresh container)", ->
    fiber.yield!
    report = apply.apply_update pkg!, {}, {}
    R.ok report.ok, "apply_update: #{report.error}"
    R.is_nil report.reinit_error, 'reinit_schema'

  R.it "the 8 data views and 4 pages are installed with the right names", ->
    vs = data_view_rows!
    for name in *EXPECTED_VIEWS
      R.ok vs[name], "vue installée manquante: #{name}"
    R.eq #([n for n in *EXPECTED_VIEWS when vs[n]]), 8, 'vues installées'
    ps = page_rows!
    for name in *EXPECTED_PAGES
      R.ok ps[name], "page installée manquante: #{name}"
    R.eq #([n for n in *EXPECTED_PAGES when ps[n]]), 4, 'pages installées'

R.describe "T16b — exécution des vues de données", ->

  R.it "Emprunts en cours — 30 lignes triées par emprunt", ->
    rows = exec_view 'Emprunts en cours'
    R.eq #rows, 30, 'nb lignes'
    for i = 2, #rows
      R.ok tostring(rows[i - 1].emprunt) <= tostring(rows[i].emprunt), "tri emprunt #{i}"

  R.it "Exemplaires disponibles — 65 lignes triées par cote", ->
    rows = exec_view 'Exemplaires disponibles'
    R.eq #rows, 65, 'nb lignes'
    for i = 2, #rows
      R.ok tostring(rows[i - 1].cote) <= tostring(rows[i].cote), "tri cote #{i}"

  R.it "Exemplaires prêtés — 30 lignes", ->
    rows = exec_view 'Exemplaires prêtés'
    R.eq #rows, 30, 'nb lignes'

  R.it "Livres sans exemplaire — 15 lignes", ->
    rows = exec_view 'Livres sans exemplaire'
    R.eq #rows, 15, 'nb lignes'

  R.it "Livres les plus empruntés — 10 lignes, nb_emprunts décroissant", ->
    rows = exec_view 'Livres les plus empruntés'
    R.eq #rows, 10, 'limit 10'
    for i = 2, #rows
      R.ok (rows[i - 1].nb_emprunts or 0) >= (rows[i].nb_emprunts or 0), "tri desc #{i}"
    R.ok rows[1] and rows[1].livre_titre, 'libellé livre_titre non vide'

  R.it "Emprunts par année — 2 groupes 90 + 30 = 120", ->
    rows = exec_view 'Emprunts par année'
    R.eq #rows, 2, '2 groupes'
    by = {}
    for r in *rows
      by[tostring r.annee_scolaire] = r.nb_emprunts
    R.eq by['2025 - 2026'], 90, '2025 - 2026'
    R.eq by['2026 - 2027'], 30, '2026 - 2027'
    sum = 0
    sum += (r.nb_emprunts or 0) for r in *rows
    R.eq sum, 120, 'somme'

  R.it "Livres par genre — somme des nb_livres = 60", ->
    rows = exec_view 'Livres par genre'
    sum = 0
    sum += (r.nb_livres or 0) for r in *rows
    R.eq sum, 60, 'somme'
    R.ok rows[1] and rows[1].genre_nom, 'libellé genre_nom non vide'

  R.it "Effectifs par classe — 5 groupes de 12", ->
    rows = exec_view 'Effectifs par classe'
    R.eq #rows, 5, '5 classes'
    for r in *rows
      R.eq r.effectif, 12, "effectif classe #{r.classe_nom}"

R.describe "T16b — pages (YAML, widgets, dépendances)", ->

  R.it "each page has a valid YAML layout and existing references", ->
    for name in *EXPECTED_PAGES
      validate_page name
