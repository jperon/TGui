-- core/widget_scopes.moon
-- Portées des définitions de widgets personnalisés (spec
-- docs/superpowers/specs/2026-11-16-custom-widgets-design.md §5).
--
-- Une ligne de `_tdb_widget_plugins` porte `app_id` en fin de format :
-- '' (ou champ absent) = bibliothèque, c'est-à-dire une définition globale ;
-- sinon l'identifiant de l'app qui la possède. Une instance de page
-- (`type: <nom>` dans le YAML) résout d'abord la définition de l'app de la
-- page, puis la globale.
--
-- L'app d'une page est celle qui l'a livrée : `_tdb_app_items` enregistre
-- `type = 'page'`, `local_id = id de la page` et l'état. Une page créée
-- localement n'appartient à aucune app : elle ne voit que la bibliothèque.
--
-- Ces fonctions sont réutilisées par l'export (core/app_package), l'installation
-- (core/app_apply), le rendu (resolvers/widget_plugin_resolvers) et la
-- suppression d'une définition : une seule résolution, jamais dupliquée.

yaml = require 'yaml'

-- Types de widgets fournis par le programme : une instance `type: table` n'est
-- pas une référence à une définition, l'export ne doit pas la collecter.
BUILTIN_WIDGET_TYPES = {
  table: true
  aggregate: true
}

-- Même motif que resolvers/widget_plugin_resolvers.validate_name : un nom est
-- une étiquette humaine (« détacher » propose « <nom> (<titre de la page>) »,
-- spec §4), d'où l'espace et les parenthèses.
NAME_PATTERN = "^[%a_\128-\255][%w_%-%.%(%) \128-\255]*$"

-- `app_id` tel qu'il est stocké ('' = bibliothèque) → forme d'API (nil).
scope_of = (raw) ->
  return raw if type(raw) == 'string' and raw != ''
  nil

-- Forme d'API (nil = bibliothèque) → valeur stockée dans le tuple.
scope_column = (app_id) ->
  return app_id if type(app_id) == 'string' and app_id != ''
  ''

-- Ligne de _tdb_widget_plugins : { id(1) name(2) … manifest(10) app_id(11) }.
row_app_id = (row) ->
  return nil unless row
  scope_of row[11]

row_name = (row) ->
  row and row[2]

-- Définition `name` dans la portée `app_id` (nil = bibliothèque), ou nil.
find_row = (name, app_id) ->
  return nil unless type(name) == 'string' and name != ''
  box.space._tdb_widget_plugins.index.by_scope_name\get { scope_column(app_id), name }

-- Toutes les définitions d'une portée exacte (nil = les globales).
rows_in_scope = (app_id) ->
  wanted = scope_column app_id
  result = {}
  for row in *box.space._tdb_widget_plugins\select {}
    table.insert result, row if scope_column(row_app_id(row)) == wanted
  result

-- Définitions visibles depuis une portée : les globales, écrasées par celles
-- de l'app quand le nom est le même. Triées par nom.
visible_for_scope = (app_id) ->
  by_name = {}
  for row in *rows_in_scope nil
    by_name[row[2]] = row
  if app_id
    for row in *rows_in_scope app_id
      by_name[row[2]] = row
  result = {}
  for _, row in pairs by_name
    table.insert result, row
  table.sort result, (a, b) -> a[2] < b[2]
  result

-- Toutes les définitions, triées par nom puis portée (bibliothèque d'abord) :
-- liste de l'éditeur, toutes portées confondues.
all_rows = ->
  rows = {}
  for row in *box.space._tdb_widget_plugins\select {}
    table.insert rows, row
  table.sort rows, (a, b) ->
    return a[2] < b[2] if a[2] != b[2]
    scope_column(row_app_id(a)) < scope_column(row_app_id(b))
  rows

-- App qui a livré la page, ou nil pour une page locale.
-- `_tdb_app_items` : app_id(1) key(2) type(3) local_id(4) fingerprint(5)
-- state(6) version(7).
page_app_id = (page_id) ->
  return nil unless type(page_id) == 'string' and page_id != ''
  for row in *box.space._tdb_app_items\select {}
    continue unless row[3] == 'page' and row[4] == page_id
    continue if row[6] == 'obsolète'
    return scope_of row[1]
  nil

-- Définition que voit une instance `name` d'une page de l'app `app_id` :
-- celle de l'app d'abord, puis la globale.
resolve_row = (name, app_id) ->
  if app_id
    row = find_row name, app_id
    return row if row
  find_row name, nil

-- Définition que voit une instance `name` de la page `page_id`.
resolve_for_page = (name, page_id) ->
  resolve_row name, page_app_id(page_id)

-- Vrai si `node` est un nœud widget du YAML de page.
is_widget_node = (node) ->
  type(node) == 'table' and type(node.widget) == 'table'

-- Noms de définitions référencés par le YAML d'une page (unique, trié).
-- Seuls les nœuds widget portent une instance ; les types fournis par le
-- programme (« table », « aggregate ») ne sont pas des références.
referenced_plugin_names = (text) ->
  names = {}
  return {} unless type(text) == 'string' and text\match '%S'

  collect = (node, depth) ->
    return unless type(node) == 'table'
    return if depth > 32
    if is_widget_node node
      widget_type = node.widget.type
      if type(widget_type) == 'string' and widget_type != '' and not BUILTIN_WIDGET_TYPES[widget_type]
        names[widget_type] = true
    for _, child in pairs node
      collect child, depth + 1 if type(child) == 'table'

  ok, parsed = pcall yaml.decode, text
  collect parsed, 0 if ok
  result = [name for name, _ in pairs names]
  table.sort result
  result

-- Définitions référencées par une page, résolues comme le rendu le fait.
referenced_rows = (page_row) ->
  return {} unless page_row
  app_id = page_app_id page_row[1]
  result = {}
  for name in *referenced_plugin_names page_row[4]
    row = resolve_row name, app_id
    table.insert result, row if row
  result

-- Pages qui utilisent effectivement cette définition : la page doit référencer
-- le nom dans un nœud widget, et la résolution (app de la page, puis globale)
-- doit tomber sur CETTE ligne. Renvoie les noms de pages, triés.
pages_using = (definition) ->
  return {} unless definition
  name = definition[2]
  result = {}
  for page in *box.space._tdb_custom_views\select {}
    used = false
    for page_name in *referenced_plugin_names page[4]
      used = true if page_name == name
    continue unless used
    resolved = resolve_row name, page_app_id(page[1])
    continue unless resolved and resolved[1] == definition[1]
    table.insert result, page[2]
  table.sort result
  result

-- Idem depuis un nom et sa portée (nil = bibliothèque).
pages_using_name = (name, app_id) ->
  row = find_row name, app_id
  return {} unless row
  pages_using row

-- Premier nom libre de la portée : `base`, sinon `base_2`, `base_3`…
-- Sert à « importer sous un autre nom » sans collision.
unique_name = (base, app_id) ->
  candidate = base
  suffix = 2
  while find_row candidate, app_id
    candidate = "#{base}_#{suffix}"
    suffix += 1
  candidate

-- Nom d'import valide : même motif que la création, longueur bornée.
valid_name = (name) ->
  type(name) == 'string' and name != '' and #name <= 120 and name\match(NAME_PATTERN) != nil

{
  :BUILTIN_WIDGET_TYPES
  :scope_of
  :scope_column
  :row_app_id
  :row_name
  :find_row
  :rows_in_scope
  :visible_for_scope
  :all_rows
  :page_app_id
  :resolve_row
  :resolve_for_page
  :referenced_plugin_names
  :referenced_rows
  :pages_using
  :pages_using_name
  :unique_name
  :valid_name
}
