local GENRES = {
  {
    'Fiction'
  },
  {
    'Roman',
    1
  },
  {
    'Policier',
    2
  },
  {
    'Science-fiction',
    2
  },
  {
    'Aventure',
    2
  },
  {
    'Théâtre',
    1
  },
  {
    'Poésie',
    1
  },
  {
    'Documentaire'
  },
  {
    'Histoire',
    8
  },
  {
    'Sciences',
    8
  },
  {
    'Biographie',
    8
  },
  {
    'Bande dessinée'
  },
  {
    'Jeunesse'
  },
  {
    'Contes',
    13
  },
  {
    'Albums',
    13
  }
}
local MOTS = {
  'aventure',
  'amitié',
  'magie',
  'enquête',
  'fantastique',
  'histoire',
  'sciences',
  'nature',
  'voyage',
  'famille',
  'courage',
  'mystère',
  'légende',
  'poésie',
  'humour',
  'dessin',
  'animaux',
  'espace',
  'mer',
  'montagne',
  'forêt',
  'ville',
  'campagne',
  'saisons',
  'rêve',
  'souvenir',
  'amour',
  'paix',
  'école',
  'jeux',
  'sport',
  'musique',
  'peinture',
  'cinéma',
  'cuisine',
  'artisanat',
  'inventions',
  'bateaux',
  'dossiers',
  'mémoires'
}
local PRENOMS = {
  'Anselme',
  'Béatrice',
  'Colin',
  'Diane',
  'Émile',
  'Flore',
  'Gaspard',
  'Hortense',
  'Irvin',
  'Joséphine',
  'Kilian',
  'Léontine',
  'Marceau',
  'Ninon',
  'Oswald',
  'Perrine',
  'Quentin',
  'Roseline',
  'Sylvain',
  'Théophile'
}
local NOMS = {
  'Aubry',
  'Belvoir',
  'Cassaigne',
  'Dunois',
  'Estève',
  'Fontaines',
  'Grévin',
  'Huart',
  'Izar',
  'Jasseron',
  'Kervegan',
  'Lantier',
  'Mesples',
  'Nogaret',
  'Orgel',
  'Peyrac',
  'Quessant',
  'Rouvière',
  'Saintelme',
  'Talhouet'
}
local PARTICULES = {
  'de',
  'du',
  'van',
  'der',
  'del',
  'le'
}
local TITRES_AUTEURS = {
  'M.',
  'Mme',
  'Dr',
  'Pr',
  'Me'
}
local ARTICLES = {
  'Le',
  'La',
  'Les',
  'Un',
  'Une',
  'Du',
  'Des'
}
local MOTS_TITRE = {
  'jardin',
  'château',
  'rivière',
  'forêt',
  'voyage',
  'secret',
  'message',
  'horizon',
  'oiseau',
  'sable',
  'vent',
  'nuage',
  'souris',
  'grenier',
  'phare',
  'passage',
  'miroir',
  'cerisier',
  'lampion',
  'tapis',
  'boussole',
  'tunnel',
  'comète',
  'abîme',
  'quai',
  'comptoir',
  'atelier',
  'labyrinthe',
  'refuge',
  'village',
  'sentier',
  'horloge'
}
local QUALIFS = {
  'bleu',
  'oublié',
  'silencieux',
  'de cristal',
  "d'automne",
  'nocturne',
  'profond',
  'invisible',
  'gai',
  'minuscule',
  'rouge',
  'vert',
  'doré',
  'poudreux',
  'ancien',
  'étrange',
  'vivant',
  'endormi',
  'fissuré',
  'bruyant',
  'timide',
  'méticuleux',
  'fragile',
  'sonore',
  'bariolé',
  'patient',
  'farcie',
  'retourné',
  'hérissé',
  'ciselé',
  'ivoire',
  'lumineux'
}
local COMMENTAIRES = {
  'Lu en classe',
  'Prêté souvent',
  'Couverture abîmée',
  'Édition originale',
  'Traduit',
  'Prix jeunesse',
  'Beaux dessins',
  'À relire',
  'Nouvelle édition',
  'Série complète'
}
local AGE_MINS = {
  3,
  5,
  6,
  8,
  10,
  12
}
local COTES = {
  'FIC',
  'POL',
  'SF',
  'JUV',
  'DOC',
  'BD',
  'THE',
  'POE'
}
local DOUBLON_TITRE = 'Le phare silencieux'
local _day0
_day0 = function(y, m, d)
  return os.time({
    year = y,
    month = m,
    day = d,
    hour = 12
  })
end
local _iso
_iso = function(t)
  return os.date('%Y-%m-%d', t)
end
local _days
_days = function(a, b)
  return math.floor((b - a) / 86400)
end
local _rand_day
_rand_day = function(rng, a, b)
  return _iso(a + rng.int(0, _days(a, b)) * 86400)
end
local ACQ_MIN = _day0(2016, 1, 1)
local ACQ_MAX = _day0(2024, 12, 31)
local SUP_MIN = _day0(2025, 1, 1)
local SUP_MAX = _day0(2026, 8, 31)
local OPEN_MIN = _day0(2026, 9, 10)
local OPEN_MAX = _day0(2026, 10, 7)
local RET_MIN = _day0(2025, 9, 15)
local RET_MAX = _day0(2026, 6, 15)
local N_OPEN = 30
local N_SUPPRESSED = 5
local _genres
_genres = function()
  local rows = { }
  for i = 1, #GENRES do
    local g = GENRES[i]
    local row = {
      id = i,
      genre = g[1]
    }
    if g[2] then
      row.parent = g[2]
    end
    table.insert(rows, row)
  end
  return rows
end
local _auteurs
_auteurs = function(rng, k)
  local rows = { }
  for i = 1, 25 * k do
    local row = {
      id = i,
      nom = rng.pick(NOMS),
      prenom = rng.pick(PRENOMS)
    }
    if i == 1 or rng.chance(0.3) then
      row.particule = rng.pick(PARTICULES)
    end
    if rng.chance(0.25) then
      row.titre = rng.pick(TITRES_AUTEURS)
    end
    table.insert(rows, row)
  end
  return rows
end
local _mots_cles
_mots_cles = function()
  local rows = { }
  for i = 1, #MOTS do
    table.insert(rows, {
      id = i,
      mot = MOTS[i]
    })
  end
  return rows
end
local _titre
_titre = function(rng)
  return tostring(rng.pick(ARTICLES)) .. " " .. tostring(rng.pick(MOTS_TITRE)) .. " " .. tostring(rng.pick(QUALIFS))
end
local _livres
_livres = function(rng, k)
  local rows = { }
  local n_auteurs = 25 * k
  for i = 1, 60 * k do
    local row = {
      id = i,
      titre = _titre(rng),
      auteur = rng.int(1, n_auteurs - 1),
      genre = rng.int(1, #GENRES)
    }
    row.note = rng.int(1, 5)
    if i <= 2 then
      row.titre = DOUBLON_TITRE
      row.auteur = 1
    end
    if rng.chance(0.35) then
      local amin = rng.pick(AGE_MINS)
      row.age_min = amin
      row.age_max = amin + rng.int(2, 6)
    end
    if rng.chance(0.3) then
      row.commentaire = rng.pick(COMMENTAIRES)
    end
    table.insert(rows, row)
  end
  return rows
end
local _livres_mots
_livres_mots = function(rng, livres)
  local rows = { }
  local id = 0
  for _index_0 = 1, #livres do
    local l = livres[_index_0]
    local a = rng.int(1, #MOTS)
    local b = rng.int(1, #MOTS - 1)
    if b >= a then
      b = b + 1
    end
    local _list_0 = {
      a,
      b
    }
    for _index_1 = 1, #_list_0 do
      local mot = _list_0[_index_1]
      id = id + 1
      table.insert(rows, {
        id = id,
        livre = l.id,
        mot_cle = mot
      })
    end
  end
  return rows
end
local _exemplaire
_exemplaire = function(rng, id, livre_id)
  return {
    id = id,
    livre = livre_id,
    cote = tostring(rng.pick(COTES)) .. "-" .. tostring(string.format('%04d', id)),
    acquisition = _rand_day(rng, ACQ_MIN, ACQ_MAX)
  }
end
local _exemplaires
_exemplaires = function(rng, k, livres)
  local with_ex = { }
  for _index_0 = 1, #livres do
    local l = livres[_index_0]
    if l.id % 4 ~= 0 then
      table.insert(with_ex, l.id)
    end
  end
  local rows = { }
  for i = 1, #with_ex do
    table.insert(rows, _exemplaire(rng, i, with_ex[i]))
  end
  for i = #with_ex + 1, 100 * k do
    table.insert(rows, _exemplaire(rng, i, rng.pick(with_ex)))
  end
  return rows
end
local _mark_suppressed
_mark_suppressed = function(rng, rows)
  local ids
  do
    local _accum_0 = { }
    local _len_0 = 1
    for _index_0 = 1, #rows do
      local r = rows[_index_0]
      _accum_0[_len_0] = r.id
      _len_0 = _len_0 + 1
    end
    ids = _accum_0
  end
  local picked = rng.shuffle(ids)
  local set = { }
  for i = 1, N_SUPPRESSED do
    set[picked[i]] = true
  end
  for _index_0 = 1, #rows do
    local r = rows[_index_0]
    if set[r.id] then
      r.suppression = _rand_day(rng, SUP_MIN, SUP_MAX)
    end
  end
  return set
end
local _returned_for
_returned_for = function(rng, ecole, ex_id, n, id0)
  local rows = { }
  local slot = math.floor(_days(RET_MIN, RET_MAX) / n)
  local id = id0
  for j = 0, n - 1 do
    id = id + 1
    local off = rng.int(0, math.max(0, slot - 45))
    local t0 = RET_MIN + (j * slot + off) * 86400
    local dur = rng.int(7, 40)
    table.insert(rows, {
      id = id,
      personne = rng.pick(ecole.eleves),
      exemplaire = ex_id,
      emprunt = _iso(t0),
      retour = _iso(t0 + dur * 86400)
    })
  end
  return rows, id
end
local _emprunts
_emprunts = function(rng, k, ecole, exemplaires, suppressed)
  local pool = { }
  for _index_0 = 1, #exemplaires do
    local e = exemplaires[_index_0]
    if not (suppressed[e.id]) then
      table.insert(pool, e.id)
    end
  end
  local rows = { }
  local shuffled = rng.shuffle(pool)
  for i = 1, N_OPEN do
    table.insert(rows, {
      id = i,
      personne = rng.pick(ecole.eleves),
      exemplaire = shuffled[i],
      emprunt = _rand_day(rng, OPEN_MIN, OPEN_MAX)
    })
  end
  local n_ret = 120 * k - N_OPEN
  local counts = { }
  for i = 1, n_ret do
    local ex = pool[(i - 1) % #pool + 1]
    counts[ex] = (counts[ex] or 0) + 1
  end
  local id = N_OPEN
  for _index_0 = 1, #pool do
    local _continue_0 = false
    repeat
      local ex = pool[_index_0]
      local c = counts[ex]
      if not (c) then
        _continue_0 = true
        break
      end
      local sub
      sub, id = _returned_for(rng, ecole, ex, c, id)
      for _index_1 = 1, #sub do
        local r = sub[_index_1]
        table.insert(rows, r)
      end
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  return rows
end
local generate
generate = function(rng, k, ecole)
  local auteurs = _auteurs(rng, k)
  local livres = _livres(rng, k)
  local lmc = _livres_mots(rng, livres)
  local exemplaires = _exemplaires(rng, k, livres)
  local suppressed = _mark_suppressed(rng, exemplaires)
  local emprunts = _emprunts(rng, k, ecole, exemplaires, suppressed)
  return {
    tables = {
      {
        space = 'Genres',
        rows = _genres()
      },
      {
        space = 'Auteurs',
        rows = auteurs
      },
      {
        space = 'MotsCles',
        rows = _mots_cles()
      },
      {
        space = 'Livres',
        rows = livres
      },
      {
        space = 'LivresMotsCles',
        rows = lmc
      },
      {
        space = 'Exemplaires',
        rows = exemplaires
      },
      {
        space = 'Emprunts',
        rows = emprunts
      }
    }
  }
end
return {
  generate = generate
}
