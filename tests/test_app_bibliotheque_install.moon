-- tests/test_app_bibliotheque_install.moon
-- T9b — l'application « Bibliothèque » est déjà INSTALLÉE au démarrage du
-- conteneur de test par backend/fixtures.moon (base vide → apply_update du
-- paquet construit par tools.bibliotheque_app). Ce test ne réinstalle rien :
-- il contrôle l'état livré par les fixtures.
--
-- Il reprend aussi les assertions de formules des trois tests de structure
-- supprimés (test_app_structure_{ecole,bibliotheque,coordonnees}.moon),
-- recalculées à partir des lignes BRUTES du seed installé plutôt qu'à partir
-- de lignes insérées à la main.

R = require 'tests.runner'
json = require 'json'
B = require 'tools.app_builder'
apply = require 'core.app_apply'
spaces = require 'core.spaces'
triggers = require 'core.triggers'
auth = require 'core.auth'
data_r = require 'resolvers.data_resolvers'

admin = auth.get_user_by_username 'admin'
CTX = { user_id: admin and admin.id }
APP_ID = 'org.tgui.bibliotheque'
-- U+2212 SIGN MINUS : le format de ecole.yaml (Niveaux.descriptif) l'utilise.
MINUS = '\226\136\146'

PKG = nil
pkg = ->
  PKG or= require('tools.bibliotheque_app').build!
  PKG

EXPECTED_COUNTS = {
  { 'Titres', 4 }
  { 'Sections', 2 }
  { 'Annee', 3 }
  { 'Niveaux', 5 }
  { 'Personnes', 72 }
  { 'Prefectures', 3 }
  { 'Classes', 10 }
  { 'ClassesEleves', 108 }
  { 'Genres', 15 }
  { 'Auteurs', 25 }
  { 'MotsCles', 40 }
  { 'Livres', 60 }
  { 'LivresMotsCles', 120 }
  { 'Exemplaires', 100 }
  { 'Emprunts', 120 }
  { 'TypesCoordonnees', 3 }
  { 'Coordonnees', 30 }
  { 'PersonnesCoordonnees', 50 }
}

LIB_NAMES = [e[1] for e in *EXPECTED_COUNTS]

-- Espaces dont le test contrôle qu'AUCUN champ calculé n'est stocké.
FORMULA_SPACES = { 'Classes', 'Livres', 'Exemplaires', 'Emprunts', 'Personnes' }

-- ── Accès aux données ────────────────────────────────────────────────────────

space_id = (name) ->
  sp = spaces.get_space_by_name name
  sp and sp.id

raw_rows = (name) ->
  out = {}
  sp = box.space["data_#{name}"]
  return out unless sp
  for t in *sp\select {}
    table.insert out, json.decode t[2]
  out

by_id = (rows) ->
  m = {}
  for r in *rows
    m[r.id] = r if r.id != nil
  m

_show = (v) ->
  return json.encode v if type(v) == 'string'
  return 'nil' if v == nil
  tostring v

-- Une formule qui dépasse la limite d'instructions renvoie une chaîne marquée
-- [ERROR|…] : on la distingue d'une valeur légitime pour diagnostiquer l'écart.
is_formula_error = (v) ->
  type(v) == 'string' and v\find('[ERROR', 1, true) != nil

-- ── Lignes brutes du seed (une seule lecture, hors formules) ────────────────

GENRES_ROWS = raw_rows 'Genres'
AUTEURS_ROWS = raw_rows 'Auteurs'
LIVRES_ROWS = raw_rows 'Livres'
EX_ROWS = raw_rows 'Exemplaires'
EMPRUNTS_ROWS = raw_rows 'Emprunts'
CE_ROWS = raw_rows 'ClassesEleves'

GENRES = by_id GENRES_ROWS
AUTEURS = by_id AUTEURS_ROWS
PERSONNES = by_id raw_rows 'Personnes'
CLASSES = by_id raw_rows 'Classes'
ANNEES_ROWS = raw_rows 'Annee'
ANNEES = by_id ANNEES_ROWS
NIVEAUX = by_id raw_rows 'Niveaux'
LIVRES = by_id LIVRES_ROWS
EX = by_id EX_ROWS
COORD_ROWS = raw_rows 'Coordonnees'
PERS_COORD_ROWS = raw_rows 'PersonnesCoordonnees'
COORDS = by_id COORD_ROWS

OPEN_LOANS = [e for e in *EMPRUNTS_ROWS when (e.retour or '') == '']
OPEN_BY_EX = {}
OPEN_BY_EX[e.exemplaire] = e for e in *OPEN_LOANS when e.exemplaire != nil

-- ── Valeurs attendues, recalculées à partir des lignes brutes ───────────────

chemin_of = (genre_id) ->
  parts = {}
  g = GENRES[genre_id]
  while g
    table.insert parts, 1, g.genre
    g = g.parent and GENRES[g.parent]
  table.concat parts, ' › '

niveau_of = (genre_id) ->
  n = 1
  g = GENRES[genre_id]
  while g and g.parent
    n += 1
    g = GENRES[g.parent]
  n

nom_complet = (a) ->
  parts = {}
  table.insert parts, a.prenom if a.prenom
  table.insert parts, a.particule if a.particule
  table.insert parts, a.nom
  table.concat parts, ' '

n_ouvrages_of = (author_id) ->
  n = 0
  for l in *LIVRES_ROWS
    n += 1 if l.auteur == author_id
  n

n_exemplaires_of = (livre_id) ->
  n = 0
  for ex in *EX_ROWS
    n += 1 if ex.livre == livre_id and (ex.suppression or '') == ''
  n

doublon_of = (l) ->
  for o in *LIVRES_ROWS
    return true if o.id != l.id and o.titre == l.titre and o.auteur == l.auteur
  false

livre_descriptif = (l) ->
  a = l.auteur and AUTEURS[l.auteur]
  name = a and nom_complet(a) or '?'
  "#{l.titre} (#{name})"

-- T16a — « libellé » d'un exemplaire : descriptif du livre + cote, même
-- séparateur U+2212 que la formule Exemplaires.descriptif.
ex_descriptif = (ex) ->
  l = ex.livre and LIVRES[ex.livre]
  base = l and livre_descriptif(l) or '?'
  base .. (ex.cote and (" #{MINUS} " .. ex.cote) or '')

emprunteur_of = (ex_id) ->
  e = OPEN_BY_EX[ex_id]
  return nil unless e
  p = PERSONNES[e.personne]
  return nil unless p
  "#{p.nom} #{p.prenom or ''}"

emprunts_en_cours_of = (person_id) ->
  n = 0
  for e in *OPEN_LOANS
    n += 1 if e.personne == person_id
  n

classe_actuelle_of = (person_id) ->
  for ce in *CE_ROWS
    if ce.eleve == person_id and (ce.depart or '') == ''
      c = CLASSES[ce.classe]
      a = c and ANNEES[c.annee]
      return ce.classe if a and a.en_cours
  nil

effectif_of = (class_id) ->
  n = 0
  for ce in *CE_ROWS
    n += 1 if ce.classe == class_id and (ce.depart or '') == ''
  n

classes_descriptif = (c) ->
  n = NIVEAUX[c.niveau]
  "#{n and n.abrege or ''}#{c.precision or ''}"

-- T16a — Classes.descriptif_complet = « <n de l'année> <descriptif> ».
classes_descriptif_complet = (c) ->
  a = c and ANNEES[c.annee]
  n = a and tonumber(a.debut\sub(1, 4))
  "#{n or '?'} #{classes_descriptif c}"

annee_label = (a) ->
  n = tonumber a.debut\sub(1, 4)
  "#{n} - #{n + 1}"

personne_descriptif = (p) ->
  s = string.upper p.nom
  s = "#{s} (#{p.particule})" if p.particule
  s = "#{s} #{p.prenom or ''}"
  s = "#{s} #{p.precision}" if p.precision
  s

niveau_descriptif = (n) ->
  string.format "%02d #{MINUS} %s", n.niveau, n.abrege

ce_annee = (ce) ->
  c = CLASSES[ce.classe]
  c and c.annee

ce_annee_en_cours = (ce) ->
  c = CLASSES[ce.classe]
  a = c and ANNEES[c.annee]
  return false unless a and a.en_cours
  return false if ce.depart
  true

emprunt_annee_en_cours = (e) ->
  for a in *ANNEES_ROWS
    return true if a.en_cours and a.debut <= e.emprunt and e.emprunt <= a.fin
  false

-- ── Lectures via data_r.Query.records (les accès proxy évaluent les formules) ─

ITEMS = {}
items_of = (name) ->
  unless ITEMS[name]
    sid = space_id name
    if sid
      ITEMS[name] = data_r.Query.records nil, { spaceId: sid, limit: 1000 }, CTX
    else
      ITEMS[name] = { items: {} }
  ITEMS[name].items

proxy_of = (name, field, value) ->
  for it in *items_of name
    return it.proxy if it.raw[field] == value
  nil

-- Compare la formule (proxy) à la valeur recalculée, agrégée par champ.
check_field = (space_name, field_name, expected_fn) ->
  rows = items_of space_name
  if #rows == 0
    R.ok false, "#{space_name}: aucune ligne — espace non installé ?"
    return
  n = 0
  bad = {}
  for it in *rows
    exp = expected_fn it.raw
    got = it.proxy[field_name]
    unless exp == got
      n += 1
      if #bad < 3
        table.insert bad, "id #{_show it.raw.id}: attendu #{_show exp}, obtenu #{_show got}"
  R.eq n, 0, "#{space_name}.#{field_name} — #{n} écart(s) #{table.concat bad, ' | '}"

-- T16a — contrôle générique d'une colonne « libellé » : >= 20 lignes, aucune
-- valeur vide, aucune valeur en erreur de formule, et égalité avec la valeur
-- recalculée en Lua à partir des lignes brutes.
check_relation_label = (space_name, field_name, expected_fn) ->
  rows = items_of space_name
  R.ok (#rows >= 20), "#{space_name}: #{#rows} ligne(s) (< 20)"
  empty, errs, mism = 0, 0, 0
  bad = {}
  for it in *rows
    got = it.proxy[field_name]
    if got == nil or got == ''
      empty += 1
    elseif is_formula_error got
      errs += 1
    else
      exp = expected_fn it.raw
      if exp != got
        mism += 1
        table.insert bad, "id #{_show it.raw.id}: attendu #{_show exp}, obtenu #{_show got}" if #bad < 3
  R.eq empty, 0, "#{space_name}.#{field_name}: #{empty} valeur(s) vide(s)"
  R.eq errs, 0, "#{space_name}.#{field_name}: #{errs} erreur(s) de formule"
  R.eq mism, 0, "#{space_name}.#{field_name}: #{mism} écart(s) #{table.concat bad, ' | '}"

-- Assertion littérale sur une ligne identifiée par un champ de valeur.
assert_proxy = (space_name, key_field, key_value, field_name, expected, label) ->
  p = proxy_of space_name, key_field, key_value
  unless p
    R.ok false, "#{label}: ligne #{_show key_value} absente de #{space_name}"
    return
  R.eq p[field_name], expected, label

-- Champs de clé étrangère du paquet, par espace source.
FK_BY_SPACE = nil
fk_by_space = ->
  return FK_BY_SPACE if FK_BY_SPACE
  FK_BY_SPACE = {}
  for item in *pkg!.items
    if item.type == 'relation'
      c = item.content
      FK_BY_SPACE[c.fromSpace] = FK_BY_SPACE[c.fromSpace] or {}
      table.insert FK_BY_SPACE[c.fromSpace], c.fromField
  FK_BY_SPACE

-- Passe hors garde d'instructions : remplit fk_cache.spaces et
-- fk_cache.fk_def_maps pour les cibles de relations (mesure T3 : construire une
-- carte de relations au sein d'une formule protégée dépasse la limite
-- d'instructions, voir rapport T9b).
warm_fk = ->
  touched = 0
  for name in *LIB_NAMES
    rows = items_of name
    for f in *(fk_by_space![name] or {})
      for it in *rows
        touched += 1 if type(it.proxy[f]) == 'table'
  touched

-- Champs calculés stockés (contrôle négatif) : renvoie les écarts trouvés.
stored_computed = (space_name, names) ->
  bad = {}
  sp = box.space["data_#{space_name}"]
  return { "espace data_#{space_name} absent" } unless sp
  for t in *sp\select {}
    row = json.decode t[2]
    for f in *names
      table.insert bad, "#{row.id}.#{f}" if row[f] != nil
  bad

formula_field_names = ->
  out = {}
  for item in *pkg!.items
    continue unless item.type == 'field'
    continue unless item.content.formula and item.content.formula != ''
    sp_name, f_name = item.key\match '^field:(.+)%.(.+)$'
    if sp_name
      out[sp_name] = out[sp_name] or {}
      table.insert out[sp_name], f_name
  out

check_formulas = ->
  checked = 0
  for name in *LIB_NAMES
    sp = spaces.get_space_by_name name
    R.ok sp, "espace #{name} non installé"
    continue unless sp
    for f in *spaces.list_fields sp.id
      continue unless f.formula and f.formula != ''
      fn = triggers.compile_formula f.formula, "#{name}.#{f.name}", f.language
      R.ok (type(fn) == 'function'), "formule non compilable #{name}.#{f.name}"
      checked += 1
  checked

-- ────────────────────────────────────────────────────────────────────────────
R.describe "bibliotheque install — état livré par les fixtures", ->

  R.it "installs every space with the exact seed row counts", ->
    for e in *EXPECTED_COUNTS
      sp = box.space["data_#{e[1]}"]
      unless sp
        R.ok false, "espace data_#{e[1]} absent"
        continue
      R.eq sp\len!, e[2], e[1]

  R.it "keeps every relation source value present in the target space", ->
    for item in *pkg!.items
      continue unless item.type == 'relation'
      c = item.content
      tgt = {}
      for r in *raw_rows c.toSpace
        tgt[tostring r[c.toField]] = true if r[c.toField] != nil
      n = 0
      sample = {}
      for r in *raw_rows c.fromSpace
        v = r[c.fromField]
        if v != nil and v != '' and not tgt[tostring v]
          n += 1
          table.insert sample, tostring v if #sample < 3
      R.eq n, 0, "#{item.key}: #{n} valeur(s) absente(s) de #{c.toSpace}.#{c.toField} #{table.concat sample, ', '}"

  R.it "stores no computed field in Classes, Livres, Exemplaires, Emprunts, Personnes", ->
    names_by_space = formula_field_names!
    for sp_name in *FORMULA_SPACES
      bad = stored_computed sp_name, names_by_space[sp_name] or {}
      R.eq #bad, 0, "#{sp_name}: champs calculés stockés #{table.concat bad, ' | '}"

-- ────────────────────────────────────────────────────────────────────────────
R.describe "bibliotheque install — formules (data_r.Query.records)", ->

  R.it "warms the foreign-key metadata caches", ->
    R.ok (warm_fk! > 0), 'aucun champ de clé étrangère résolu'

  R.it "compiles every formula of the installed spaces (anciens tests T3/T4)", ->
    R.ok (check_formulas! > 0), 'aucune formule dans les espaces installés'

  -- Reprise de tests/test_app_structure_ecole.moon (T3).
  R.it "T3 — ecole formulas recomputed from the installed seed", ->
    check_field 'Annee', 'annee', (a) -> annee_label a
    check_field 'Niveaux', 'descriptif', (n) -> niveau_descriptif n
    check_field 'Personnes', 'descriptif', (p) -> personne_descriptif p
    check_field 'Personnes', 'classe_actuelle', (p) -> classe_actuelle_of p.id
    check_field 'Personnes', 'emprunts_en_cours', (p) -> emprunts_en_cours_of p.id
    check_field 'Classes', 'effectif', (c) -> effectif_of c.id
    check_field 'Classes', 'descriptif', (c) -> classes_descriptif c
    check_field 'ClassesEleves', 'annee', (ce) -> ce_annee ce
    check_field 'ClassesEleves', 'annee_en_cours', (ce) -> ce_annee_en_cours ce

  R.it "T3 — literal school values", ->
    assert_proxy 'Annee', 'id', 3, 'annee', '2026 - 2027', 'Annee.annee de l’année en cours'
    assert_proxy 'Niveaux', 'id', 1, 'descriptif', "01 #{MINUS} CP", 'Niveaux.descriptif du CP'
    assert_proxy 'Classes', 'id', 6, 'effectif', 12, 'Classes.effectif de la classe 6'
    assert_proxy 'Personnes', 'id', 1, 'classe_actuelle', nil, 'classe_actuelle d’un adulte (cas 4)'

  R.it "T3 — a level-1 student has classe_actuelle = 6", ->
    sid = nil
    for ce in *CE_ROWS
      c = CLASSES[ce.classe]
      a = c and ANNEES[c.annee]
      if c and a and a.en_cours and not ce.depart and c.niveau == 1
        sid = ce.eleve
        break
    R.ok sid, 'aucun élève de niveau 1 dans la classe de l’année en cours'
    assert_proxy 'Personnes', 'id', sid, 'classe_actuelle', 6, 'classe_actuelle d’un élève de niveau 1' if sid

  -- Reprise de tests/test_app_structure_bibliotheque.moon (T4).
  R.it "T4 — library formulas recomputed from the installed seed", ->
    check_field 'Genres', 'niveau', (g) -> niveau_of g.id
    check_field 'Genres', 'chemin', (g) -> chemin_of g.id
    check_field 'Auteurs', 'nom_complet', (a) -> nom_complet a
    check_field 'Auteurs', 'n_ouvrages', (a) -> n_ouvrages_of a.id
    check_field 'Livres', 'n_exemplaires', (l) -> n_exemplaires_of l.id
    check_field 'Livres', 'doublon', (l) -> doublon_of l
    check_field 'Livres', 'descriptif', (l) -> livre_descriptif l
    check_field 'Exemplaires', 'emprunteur', (e) -> emprunteur_of e.id

  R.it "T4 — literal library values", ->
    assert_proxy 'Genres', 'id', 3, 'chemin', 'Fiction › Roman › Policier', 'Genres.chemin du genre 3'
    assert_proxy 'Genres', 'id', 1, 'niveau', 1, 'Genres.niveau du genre racine'
    assert_proxy 'Genres', 'id', 1, 'chemin', 'Fiction', 'Genres.chemin du genre racine'
    total, errs, zeros = 0, 0, 0
    for it in *items_of 'Auteurs'
      v = it.proxy.n_ouvrages
      if type(v) == 'number'
        total += v
      elseif v != nil
        errs += 1
      zeros += 1 if v == 0
    R.eq total, 60, "somme de Auteurs.n_ouvrages (#{errs} valeur(s) en erreur de formule)"
    R.ok zeros > 0, "au moins un auteur sans livre (cas 3) (#{errs} erreur(s))"
    dbl_t, dbl_f, zero_ex, dbl_err = 0, 0, 0, 0
    for it in *items_of 'Livres'
      d = it.proxy.doublon
      if d == true
        dbl_t += 1
      elseif d == false
        dbl_f += 1
      else
        dbl_err += 1
      zero_ex += 1 if (it.proxy.n_exemplaires or 0) == 0
    R.ok dbl_t > 0, "au moins un doublon vrai (#{dbl_err} valeur(s) en erreur)"
    R.ok dbl_f > 0, "au moins un doublon faux (#{dbl_err} valeur(s) en erreur)"
    R.ok zero_ex > 0, 'au moins un livre sans exemplaire (cas 3)'

  -- Reprise de tests/test_app_structure_coordonnees.moon (T5) : coordonnées.
  R.it "T5 — contact types, N-N shared coordonnée, notNull refusal", ->
    types = {}
    types[r.type] = true for r in *raw_rows 'TypesCoordonnees' when r.type != nil
    for t in *{ 'tel', 'courriel', 'adresse' }
      R.ok types[t], "type de coordonnée '#{t}'"
    links = raw_rows 'PersonnesCoordonnees'
    counts = {}
    for l in *links
      counts[l.coordonnee] = (counts[l.coordonnee] or 0) + 1 if l.coordonnee != nil
    shared = {}
    for cid, n in pairs counts
      table.insert shared, cid if n >= 2
    R.ok #shared > 0, 'aucune coordonnée partagée par deux personnes (liaison N-N)'
    if #shared > 0
      seen = {}
      distinct = 0
      for l in *links
        if l.coordonnee == shared[1] and not seen[l.personne]
          seen[l.personne] = true
          distinct += 1
      R.ok distinct >= 2, 'la coordonnée partagée lie deux personnes distinctes'
    coord_sp = box.space["data_Coordonnees"]
    unless coord_sp
      R.ok false, 'espace data_Coordonnees absent'
      return
    nb_before = coord_sp\len!
    insert_without_valeur = ->
      data_r.Mutation.insertRecord {}, {
        spaceId: space_id('Coordonnees')
        data: { type_coordonnee: 1 }
      }, CTX
    R.raises insert_without_valeur, 'not_null', 'valeur required'
    R.eq coord_sp\len!, nb_before, 'aucune ligne écrite'

  -- Reprise de T9b §3.4 : emprunts de l'année en cours.
  R.it "T9b — Emprunts.annee_en_cours is true for exactly 30 emprunts", ->
    check_field 'Emprunts', 'annee_en_cours', (e) -> emprunt_annee_en_cours e
    n = 0
    for it in *items_of 'Emprunts'
      n += 1 if it.proxy.annee_en_cours
    R.eq n, 30, 'Emprunts.annee_en_cours vrai'
    open, open_err = 0, 0
    for it in *items_of 'Exemplaires'
      v = it.proxy.emprunteur
      if type(v) == 'string' and not is_formula_error(v)
        open += 1
      elseif v != nil
        open_err += 1
    R.eq open, 30, "Exemplaires.emprunteur non vide (#{open_err} valeur(s) en erreur de formule)"
    total, errs = 0, 0
    for it in *items_of 'Personnes'
      v = it.proxy.emprunts_en_cours
      if type(v) == 'number'
        total += v
      elseif v != nil
        errs += 1
    R.eq total, 30, "somme de Personnes.emprunts_en_cours (#{errs} valeur(s) en erreur de formule)"

  -- T16a — colonnes calculées « libellé » : noms lisibles à la place des ids.
  R.it "T16a — relation labels match the raw seed", ->
    check_relation_label 'Emprunts', 'lecteur', (e) -> personne_descriptif PERSONNES[e.personne]
    check_relation_label 'Emprunts', 'ouvrage', (e) -> ex_descriptif EX[e.exemplaire]
    check_relation_label 'Exemplaires', 'livre_titre', (e) -> LIVRES[e.livre].titre
    check_relation_label 'Livres', 'auteur_nom', (l) -> nom_complet AUTEURS[l.auteur]
    check_relation_label 'Livres', 'genre_nom', (l) -> chemin_of l.genre
    check_relation_label 'ClassesEleves', 'eleve_nom', (ce) -> personne_descriptif PERSONNES[ce.eleve]
    check_relation_label 'ClassesEleves', 'classe_nom', (ce) -> classes_descriptif_complet CLASSES[ce.classe]
    check_relation_label 'PersonnesCoordonnees', 'personne_nom', (pc) -> personne_descriptif PERSONNES[pc.personne]
    check_relation_label 'PersonnesCoordonnees', 'coordonnee_valeur', (pc) -> COORDS[pc.coordonnee].valeur

  R.it "T16a — the package gained the nine label formulas", ->
    names = formula_field_names!
    total = 0
    for _, lst in pairs names
      total += #lst
    R.eq total, 38, "nombre total de champs calculés (29 avant T16a + 9)"
    wanted = {
      { 'Emprunts', 'lecteur' }, { 'Emprunts', 'ouvrage' }
      { 'Exemplaires', 'livre_titre' }
      { 'Livres', 'auteur_nom' }, { 'Livres', 'genre_nom' }
      { 'ClassesEleves', 'eleve_nom' }, { 'ClassesEleves', 'classe_nom' }
      { 'PersonnesCoordonnees', 'personne_nom' }, { 'PersonnesCoordonnees', 'coordonnee_valeur' }
    }
    for w in *wanted
      found = false
      found = true for f in *(names[w[1]] or {}) when f == w[2]
      R.ok found, "champ calculé manquant #{w[1]}.#{w[2]}"

-- ────────────────────────────────────────────────────────────────────────────
R.describe "bibliotheque install — contrat applicatif", ->

  R.it "apply_update of the same package creates and updates nothing", ->
    report = apply.apply_update pkg!, {}, {}
    R.ok report.ok, "apply_update: #{report.error}"
    R.is_nil report.reinit_error, 'reinit_schema'
    R.eq #(report.created or {}), 0, 'created'
    R.eq #(report.updated or {}), 0, 'updated'

  R.it "insertRecord gets an id above every seed id, then restores the row counts", ->
    specs = {
      { 'Livres', { titre: 'T9b', auteur: 1, genre: 1 } }
      { 'Personnes', { nom: 'T9b', prenom: 'X' } }
      { 'Emprunts', { personne: 13, exemplaire: 1, emprunt: '2026-10-08' } }
    }
    for spec in *specs
      name, data = spec[1], spec[2]
      sp = box.space["data_#{name}"]
      unless sp
        R.ok false, "espace data_#{name} absent"
        continue
      count_before = sp\len!
      max_before = 0
      for r in *raw_rows name
        max_before = r.id if type(r.id) == 'number' and r.id > max_before
      rec = data_r.Mutation.insertRecord {}, {
        spaceId: space_id(name), data: data }, CTX
      new_id = json.decode(rec.data).id
      if type(new_id) != 'number'
        R.ok false, "#{name}: id attribué #{_show new_id} (séquence absente ?)"
      else
        R.ok new_id > max_before, "#{name}: id #{_show new_id} > seed max #{max_before}"
      data_r.Mutation.deleteRecord {}, { spaceId: space_id(name), id: rec.id }, CTX
      R.eq sp\len!, count_before, "#{name}: comptes rétablis"

  R.it "emit(build()) is byte-identical on two calls", ->
    a = B.emit pkg!
    b = B.emit require('tools.bibliotheque_app').build!
    R.ok (a == b), "emit(build()) diffère (#{#a} vs #{#b} octets)"

