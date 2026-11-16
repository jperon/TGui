local PRENOMS_M = {
  'Antoine',
  'Bastien',
  'Cédric',
  'Damien',
  'Émile',
  'Florian',
  'Gaël',
  'Hugo',
  'Isidore',
  'Jérôme',
  'Kilian',
  'Loïc',
  'Marcel',
  'Nathan',
  'Oscar',
  'Patrice',
  'Quentin',
  'Raphaël'
}
local PRENOMS_F = {
  'Adèle',
  'Béatrice',
  'Clémence',
  'Delphine',
  'Éloïse',
  'Flore',
  'Garance',
  'Hélène',
  'Inès',
  'Joséphine',
  'Karine',
  'Lucie',
  'Marion',
  'Noémie',
  'Océane',
  'Priscille',
  'Rosalie',
  'Solène'
}
local NOMS = {
  'Aubert',
  'Bélanger',
  'Chevrier',
  'Dauvers',
  'Émery',
  'Fauvel',
  'Grangier',
  'Hurtaud',
  'Imbert',
  'Jourdan',
  'Lambert',
  'Montel',
  'Noizet',
  'Perrin',
  'Rouvier',
  'Seguin',
  'Tardif',
  'Vasseur'
}
local PROF_IDS = {
  1,
  2,
  3,
  4,
  5
}
local PREFET_IDS = {
  6,
  7
}
local PARENT_IDS = {
  8,
  9,
  10,
  11,
  12
}
local NIVEAUX_NOMS = {
  {
    abrege = 'CP',
    classe = 'Cours préparatoire'
  },
  {
    abrege = 'CE1',
    classe = 'Cours élémentaire 1'
  },
  {
    abrege = 'CE2',
    classe = 'Cours élémentaire 2'
  },
  {
    abrege = 'CM1',
    classe = 'Cours moyen 1'
  },
  {
    abrege = 'CM2',
    classe = 'Cours moyen 2'
  }
}
local _adulte_titre
_adulte_titre = function(rng, i)
  if i == 3 then
    return 3
  end
  if i == 4 then
    return 4
  end
  return rng.chance(0.5) and 1 or 2
end
local _gen_titres
_gen_titres = function()
  return {
    {
      id = 1,
      titre = 'M.',
      abrege = 'M.',
      femme = false
    },
    {
      id = 2,
      titre = 'Mme',
      abrege = 'Mme',
      femme = true
    },
    {
      id = 3,
      titre = 'Frère',
      abrege = 'Fr.',
      femme = false
    },
    {
      id = 4,
      titre = 'Sœur',
      abrege = 'S.',
      femme = true
    }
  }
end
local _gen_sections
_gen_sections = function()
  return {
    {
      id = 1,
      section = 'Générale',
      abregee = 'GEN'
    },
    {
      id = 2,
      section = 'Bilingue',
      abregee = 'BIL'
    }
  }
end
local _gen_annee
_gen_annee = function()
  return {
    {
      id = 1,
      debut = '2024-09-01',
      fin = '2025-06-30',
      en_cours = false,
      section = 1
    },
    {
      id = 2,
      debut = '2025-09-01',
      fin = '2026-06-30',
      en_cours = false,
      section = 1
    },
    {
      id = 3,
      debut = '2026-09-01',
      fin = '2027-06-30',
      en_cours = true,
      section = 1
    }
  }
end
local _gen_niveaux
_gen_niveaux = function()
  local rows = { }
  for i = 1, 5 do
    local n = NIVEAUX_NOMS[i]
    local row = {
      id = i,
      niveau = i,
      classe = n.classe,
      abrege = n.abrege,
      generique = 'Primaire'
    }
    if i < 5 then
      row.superieur = i + 1
    end
    table.insert(rows, row)
  end
  return rows
end
local _gen_adultes
_gen_adultes = function(rng)
  local rows = { }
  for i = 1, 12 do
    local titre = _adulte_titre(rng, i)
    local male = titre == 1 or titre == 3
    local annee = 1970 + 2 * i
    local row = {
      id = i,
      nom = rng.pick(NOMS),
      prenom = male and rng.pick(PRENOMS_M) or rng.pick(PRENOMS_F),
      titre = titre,
      date_de_naissance = tostring(annee) .. "-05-20"
    }
    if rng.chance(0.25) then
      row.particule = 'de'
    end
    table.insert(rows, row)
  end
  return rows
end
local _eleve_row
_eleve_row = function(rng, id, niveau)
  local male = rng.chance(0.5)
  local annee = 2021 - niveau
  return {
    id = id,
    niveau = niveau,
    nom = rng.pick(NOMS),
    prenom = male and rng.pick(PRENOMS_M) or rng.pick(PRENOMS_F),
    date_de_naissance = tostring(annee) .. "-09-01",
    famille = rng.pick(PARENT_IDS)
  }
end
local _gen_eleves
_gen_eleves = function(rng, k)
  local students = { }
  local id = 12
  for niveau = 1, 5 do
    for _n = 1, 12 * k do
      id = id + 1
      table.insert(students, _eleve_row(rng, id, niveau))
    end
  end
  return students
end
local _personnes_rows
_personnes_rows = function(adultes, students)
  local rows = { }
  for _index_0 = 1, #adultes do
    local r = adultes[_index_0]
    table.insert(rows, r)
  end
  for _index_0 = 1, #students do
    local s = students[_index_0]
    table.insert(rows, {
      id = s.id,
      nom = s.nom,
      prenom = s.prenom,
      date_de_naissance = s.date_de_naissance,
      famille = s.famille
    })
  end
  return rows
end
local _gen_prefectures
_gen_prefectures = function(rng)
  local rows = { }
  for annee_id = 1, 3 do
    table.insert(rows, {
      id = annee_id,
      nom = 'Préfecture',
      annee = annee_id,
      prefet = rng.pick(PREFET_IDS),
      niveau_min = 1,
      niveau_max = 5
    })
  end
  return rows
end
local _classe_row
_classe_row = function(rng, id, niveau, annee_id)
  return {
    id = id,
    niveau = niveau,
    annee = annee_id,
    prefecture = annee_id,
    professeur_principal = rng.pick(PROF_IDS)
  }
end
local _gen_classes
_gen_classes = function(rng)
  local rows = { }
  for annee_id = 2, 3 do
    for niveau = 1, 5 do
      local id = (annee_id - 2) * 5 + niveau
      table.insert(rows, _classe_row(rng, id, niveau, annee_id))
    end
  end
  return rows
end
local _classes_eleves_rows
_classes_eleves_rows = function(students)
  local rows = { }
  local id = 0
  for _index_0 = 1, #students do
    local s = students[_index_0]
    id = id + 1
    table.insert(rows, {
      id = id,
      classe = 5 + s.niveau,
      eleve = s.id,
      entree = '2026-09-01'
    })
    if s.niveau >= 2 then
      id = id + 1
      table.insert(rows, {
        id = id,
        classe = s.niveau - 1,
        eleve = s.id,
        entree = '2025-09-01',
        depart = '2026-06-30',
        redoublement = false
      })
    end
  end
  return rows
end
local generate
generate = function(rng, k)
  local adultes_rows = _gen_adultes(rng)
  local students = _gen_eleves(rng, k)
  local tables = { }
  local add
  add = function(space, rows)
    return table.insert(tables, {
      space = space,
      rows = rows
    })
  end
  add('Titres', _gen_titres())
  add('Sections', _gen_sections())
  add('Annee', _gen_annee())
  add('Niveaux', _gen_niveaux())
  add('Personnes', _personnes_rows(adultes_rows, students))
  add('Prefectures', _gen_prefectures(rng))
  add('Classes', _gen_classes(rng))
  add('ClassesEleves', _classes_eleves_rows(students))
  local adultes
  do
    local _accum_0 = { }
    local _len_0 = 1
    for _index_0 = 1, #adultes_rows do
      local r = adultes_rows[_index_0]
      _accum_0[_len_0] = r.id
      _len_0 = _len_0 + 1
    end
    adultes = _accum_0
  end
  local eleves
  do
    local _accum_0 = { }
    local _len_0 = 1
    for _index_0 = 1, #students do
      local s = students[_index_0]
      _accum_0[_len_0] = s.id
      _len_0 = _len_0 + 1
    end
    eleves = _accum_0
  end
  local personnes = { }
  for _index_0 = 1, #adultes do
    local id = adultes[_index_0]
    table.insert(personnes, id)
  end
  for _index_0 = 1, #eleves do
    local id = eleves[_index_0]
    table.insert(personnes, id)
  end
  return {
    tables = tables,
    eleves = eleves,
    adultes = adultes,
    personnes = personnes
  }
end
return {
  generate = generate
}
