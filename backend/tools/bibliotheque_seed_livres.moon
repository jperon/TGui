-- tools/bibliotheque_seed_livres.moon — données fictives « bibliothèque » (T7).
--
-- Interface : generate(rng, k, ecole) -> out
--   rng   : outil tools.seed_rng (déterministe)
--   k     : facteur d'échelle (entier ≥ 1)
--   ecole : { eleves = {ids}, personnes = {ids} }
--   out.tables : sept tables dans l'ordre Genres, Auteurs, MotsCles, Livres,
--                LivresMotsCles, Exemplaires, Emprunts.
-- Conventions T6 : ids entiers explicites, champs vides omis, dates ISO.
-- Aucune donnée personnelle réelle : prénoms, noms et titres inventés.

-- ── Référentiels fixes (indépendants de k) ──────────────────────────────────
GENRES = {
  { 'Fiction' }
  { 'Roman', 1 }
  { 'Policier', 2 }
  { 'Science-fiction', 2 }
  { 'Aventure', 2 }
  { 'Théâtre', 1 }
  { 'Poésie', 1 }
  { 'Documentaire' }
  { 'Histoire', 8 }
  { 'Sciences', 8 }
  { 'Biographie', 8 }
  { 'Bande dessinée' }
  { 'Jeunesse' }
  { 'Contes', 13 }
  { 'Albums', 13 }
}

MOTS = {
  'aventure', 'amitié', 'magie', 'enquête', 'fantastique', 'histoire', 'sciences'
  'nature', 'voyage', 'famille', 'courage', 'mystère', 'légende', 'poésie', 'humour'
  'dessin', 'animaux', 'espace', 'mer', 'montagne', 'forêt', 'ville', 'campagne'
  'saisons', 'rêve', 'souvenir', 'amour', 'paix', 'école', 'jeux', 'sport', 'musique'
  'peinture', 'cinéma', 'cuisine', 'artisanat', 'inventions', 'bateaux', 'dossiers'
  'mémoires'
}

PRENOMS = {
  'Anselme', 'Béatrice', 'Colin', 'Diane', 'Émile', 'Flore', 'Gaspard', 'Hortense'
  'Irvin', 'Joséphine', 'Kilian', 'Léontine', 'Marceau', 'Ninon', 'Oswald', 'Perrine'
  'Quentin', 'Roseline', 'Sylvain', 'Théophile'
}

NOMS = {
  'Aubry', 'Belvoir', 'Cassaigne', 'Dunois', 'Estève', 'Fontaines', 'Grévin', 'Huart'
  'Izar', 'Jasseron', 'Kervegan', 'Lantier', 'Mesples', 'Nogaret', 'Orgel', 'Peyrac'
  'Quessant', 'Rouvière', 'Saintelme', 'Talhouet'
}

PARTICULES = { 'de', 'du', 'van', 'der', 'del', 'le' }
TITRES_AUTEURS = { 'M.', 'Mme', 'Dr', 'Pr', 'Me' }

ARTICLES = { 'Le', 'La', 'Les', 'Un', 'Une', 'Du', 'Des' }

MOTS_TITRE = {
  'jardin', 'château', 'rivière', 'forêt', 'voyage', 'secret', 'message', 'horizon'
  'oiseau', 'sable', 'vent', 'nuage', 'souris', 'grenier', 'phare', 'passage'
  'miroir', 'cerisier', 'lampion', 'tapis', 'boussole', 'tunnel', 'comète', 'abîme'
  'quai', 'comptoir', 'atelier', 'labyrinthe', 'refuge', 'village', 'sentier'
  'horloge'
}

QUALIFS = {
  'bleu', 'oublié', 'silencieux', 'de cristal', "d'automne", 'nocturne', 'profond'
  'invisible', 'gai', 'minuscule', 'rouge', 'vert', 'doré', 'poudreux', 'ancien'
  'étrange', 'vivant', 'endormi', 'fissuré', 'bruyant', 'timide', 'méticuleux'
  'fragile', 'sonore', 'bariolé', 'patient', 'farcie', 'retourné', 'hérissé'
  'ciselé', 'ivoire', 'lumineux'
}

COMMENTAIRES = {
  'Lu en classe', 'Prêté souvent', 'Couverture abîmée', 'Édition originale'
  'Traduit', 'Prix jeunesse', 'Beaux dessins', 'À relire', 'Nouvelle édition'
  'Série complète'
}

AGE_MINS = { 3, 5, 6, 8, 10, 12 }
COTES = { 'FIC', 'POL', 'SF', 'JUV', 'DOC', 'BD', 'THE', 'POE' }

-- Les livres 1 et 2 portent ce même titre et ce même auteur : ils exercent la
-- formule `Livres.doublon`.
DOUBLON_TITRE = 'Le phare silencieux'

-- ── Dates (chaînes ISO, arithmétique de jours via os.time/os.date) ──────────
_day0 = (y, m, d) -> os.time { year: y, month: m, day: d, hour: 12 }
_iso = (t) -> os.date '%Y-%m-%d', t
_days = (a, b) -> math.floor((b - a) / 86400)
_rand_day = (rng, a, b) -> _iso(a + rng.int(0, _days(a, b)) * 86400)

ACQ_MIN = _day0(2016, 1, 1)
ACQ_MAX = _day0(2024, 12, 31)
SUP_MIN = _day0(2025, 1, 1)
SUP_MAX = _day0(2026, 8, 31)
OPEN_MIN = _day0(2026, 9, 10)
OPEN_MAX = _day0(2026, 10, 7)
RET_MIN = _day0(2025, 9, 15)
RET_MAX = _day0(2026, 6, 15)

N_OPEN = 30
N_SUPPRESSED = 5

-- ── Générateurs ─────────────────────────────────────────────────────────────
_genres = ->
  rows = {}
  for i = 1, #GENRES
    g = GENRES[i]
    row = { id: i, genre: g[1] }
    row.parent = g[2] if g[2]
    table.insert rows, row
  rows

_auteurs = (rng, k) ->
  rows = {}
  for i = 1, 25 * k
    row = { id: i, nom: rng.pick(NOMS), prenom: rng.pick(PRENOMS) }
    -- le premier auteur porte toujours une particule (test T7)
    row.particule = rng.pick PARTICULES if i == 1 or rng.chance 0.3
    row.titre = rng.pick TITRES_AUTEURS if rng.chance 0.25
    table.insert rows, row
  rows

_mots_cles = ->
  rows = {}
  for i = 1, #MOTS
    table.insert rows, { id: i, mot: MOTS[i] }
  rows

_titre = (rng) -> "#{rng.pick(ARTICLES)} #{rng.pick(MOTS_TITRE)} #{rng.pick(QUALIFS)}"

_livres = (rng, k) ->
  rows = {}
  n_auteurs = 25 * k
  for i = 1, 60 * k
    row = {
      id: i
      titre: _titre(rng)
      auteur: rng.int(1, n_auteurs - 1)
      genre: rng.int(1, #GENRES)
    }
    row.note = rng.int 1, 5
    if i <= 2
      row.titre = DOUBLON_TITRE
      row.auteur = 1
    if rng.chance 0.35
      amin = rng.pick AGE_MINS
      row.age_min = amin
      row.age_max = amin + rng.int(2, 6)
    row.commentaire = rng.pick COMMENTAIRES if rng.chance 0.3
    table.insert rows, row
  rows

_livres_mots = (rng, livres) ->
  rows = {}
  id = 0
  for l in *livres
    a = rng.int 1, #MOTS
    b = rng.int 1, #MOTS - 1
    b += 1 if b >= a
    for mot in *{ a, b }
      id += 1
      table.insert rows, { id: id, livre: l.id, mot_cle: mot }
  rows

_exemplaire = (rng, id, livre_id) ->
  {
    id: id
    livre: livre_id
    cote: "#{rng.pick(COTES)}-#{string.format('%04d', id)}"
    acquisition: _rand_day(rng, ACQ_MIN, ACQ_MAX)
  }

_exemplaires = (rng, k, livres) ->
  -- un livre sur quatre n'a aucun exemplaire
  with_ex = {}
  for l in *livres
    table.insert with_ex, l.id if l.id % 4 != 0
  rows = {}
  for i = 1, #with_ex
    table.insert rows, _exemplaire(rng, i, with_ex[i])
  for i = #with_ex + 1, 100 * k
    table.insert rows, _exemplaire(rng, i, rng.pick(with_ex))
  rows

-- Marque 5 exemplaires comme supprimés ; renvoie l'ensemble de leurs ids.
_mark_suppressed = (rng, rows) ->
  ids = [r.id for r in *rows]
  picked = rng.shuffle ids
  set = {}
  for i = 1, N_SUPPRESSED
    set[picked[i]] = true
  for r in *rows
    r.suppression = _rand_day(rng, SUP_MIN, SUP_MAX) if set[r.id]
  set

-- Prêts rendus d'un exemplaire : fenêtres disjointes (au plus `n` prêts,
-- emprunt dans [RET_MIN, RET_MAX], retour 7 à 40 jours après).
-- Renvoie les lignes et le dernier id utilisé.
_returned_for = (rng, ecole, ex_id, n, id0) ->
  rows = {}
  slot = math.floor(_days(RET_MIN, RET_MAX) / n)
  id = id0
  for j = 0, n - 1
    id += 1
    off = rng.int(0, math.max(0, slot - 45))
    t0 = RET_MIN + (j * slot + off) * 86400
    dur = rng.int 7, 40
    table.insert rows, {
      id: id
      personne: rng.pick(ecole.eleves)
      exemplaire: ex_id
      emprunt: _iso(t0)
      retour: _iso(t0 + dur * 86400)
    }
  rows, id

_emprunts = (rng, k, ecole, exemplaires, suppressed) ->
  pool = {}
  for e in *exemplaires
    table.insert pool, e.id unless suppressed[e.id]
  rows = {}
  -- prêts non rendus : un seul par exemplaire, jamais sur un exemplaire supprimé
  shuffled = rng.shuffle pool
  for i = 1, N_OPEN
    table.insert rows, {
      id: i
      personne: rng.pick(ecole.eleves)
      exemplaire: shuffled[i]
      emprunt: _rand_day(rng, OPEN_MIN, OPEN_MAX)
    }
  -- prêts rendus : répartis en round-robin sur le même pool
  n_ret = 120 * k - N_OPEN
  counts = {}
  for i = 1, n_ret
    ex = pool[(i - 1) % #pool + 1]
    counts[ex] = (counts[ex] or 0) + 1
  id = N_OPEN
  for ex in *pool
    c = counts[ex]
    continue unless c
    sub, id = _returned_for(rng, ecole, ex, c, id)
    table.insert rows, r for r in *sub
  rows

generate = (rng, k, ecole) ->
  auteurs = _auteurs rng, k
  livres = _livres rng, k
  lmc = _livres_mots rng, livres
  exemplaires = _exemplaires rng, k, livres
  suppressed = _mark_suppressed rng, exemplaires
  emprunts = _emprunts rng, k, ecole, exemplaires, suppressed
  {
    tables: {
      { space: 'Genres', rows: _genres! }
      { space: 'Auteurs', rows: auteurs }
      { space: 'MotsCles', rows: _mots_cles! }
      { space: 'Livres', rows: livres }
      { space: 'LivresMotsCles', rows: lmc }
      { space: 'Exemplaires', rows: exemplaires }
      { space: 'Emprunts', rows: emprunts }
    }
  }

{ :generate }
