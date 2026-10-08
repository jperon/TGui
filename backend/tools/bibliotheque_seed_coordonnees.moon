-- tools/bibliotheque_seed_coordonnees.moon — données fictives : coordonnées.
-- Interface : generate(rng, k, ecole) -> out
--   out.tables, dans l'ordre TypesCoordonnees, Coordonnees, PersonnesCoordonnees.
--   ecole.personnes = ids des personnes (factices 1..72 dans le test).
-- Volumes à k = 1 : 3 types, 30 coordonnées, 50 liaisons.
-- Toutes les valeurs sont fictives : numéros sous le préfixe réservé 06 00 00,
-- courriels en @exemple.invalid (domaine RFC 2606), adresses inventées.

TYPES = { 'tel', 'courriel', 'adresse' }
LIBELLES = { 'domicile', 'parents', 'travail' }
VOIES = { 'rue', 'avenue', 'chemin', 'place', 'quai', 'impasse', 'boulevard', 'cours', 'sentier' }
RUES = { 'Lumènes', 'Zébrels', 'Orchandes', 'Brumillons', 'Castorêts', 'Dorimèdes',
  'Étherlins', 'Fulgorions', 'Glyptores', 'Néphélins', 'Pétrasons', 'Volérives',
  'Aurorelles', 'Claironnets', 'Mésangeots', 'Roncevoies' }
PARTIES = { 'ada', 'bob', 'cami', 'dan', 'eva', 'fifi', 'gus', 'hugo', 'iris', 'jules',
  'kate', 'leo', 'mira', 'nino', 'olive', 'paul' }

_tel = (rng) -> "06 00 00 #{rng.int 10, 99} #{rng.int 10, 99}"

_courriel = (rng) -> "#{rng.pick PARTIES}.#{rng.pick PARTIES}#{rng.int 1, 999}@exemple.invalid"

_adresse = (rng) -> "#{rng.int 1, 150} #{rng.pick VOIES} des #{rng.pick RUES}"

_valeur = (rng, t) ->
  return _tel(rng) if t == 1
  return _courriel(rng) if t == 2
  _adresse(rng)

_type_for = (i) -> (i - 1) % 3 + 1

-- Liaisons N-N : la première boucle couvre chaque coordonnée avec une personne
-- tirée au hasard (couples distincts puisque la coordonnée est unique), la
-- seconde relie les 20*k premières coordonnées à une personne différente — ce
-- sont ces coordonnées-là qui sont partagées. Sans personne (ecole.personnes
-- vide) ou avec une seule personne, la seconde boucle ne peut pas produire de
-- couple distinct : elle est sautée.
_links = (rng, personnes, n_coords, n_links) ->
  out = {}
  return out if #personnes == 0
  owner = {}
  for c = 1, n_coords
    p = rng.pick personnes
    owner[c] = p
    table.insert out, { id: #out + 1, personne: p, coordonnee: c, libelle: rng.pick(LIBELLES) }
  for c = 1, n_links - n_coords
    p1 = owner[c]
    continue if not p1
    others = [p for p in *personnes when p != p1]
    continue if #others == 0
    table.insert out, { id: #out + 1, personne: rng.pick(others), coordonnee: c, libelle: rng.pick(LIBELLES) }
  out

generate = (rng, k, ecole) ->
  personnes = (ecole and ecole.personnes) or {}
  n_coords = 30 * k
  n_links = 50 * k
  types_rows = {}
  for i = 1, #TYPES
    table.insert types_rows, { id: i, type: TYPES[i] }
  coord_rows = {}
  for i = 1, n_coords
    t = _type_for i
    table.insert coord_rows, { id: i, type_coordonnee: t, valeur: _valeur(rng, t) }
  links = _links rng, personnes, n_coords, n_links
  tables = {
    { space: 'TypesCoordonnees', rows: types_rows }
    { space: 'Coordonnees', rows: coord_rows }
    { space: 'PersonnesCoordonnees', rows: links }
  }
  { tables: tables }

{ :generate }
