local TYPES = {
  'tel',
  'courriel',
  'adresse'
}
local LIBELLES = {
  'domicile',
  'parents',
  'travail'
}
local VOIES = {
  'rue',
  'avenue',
  'chemin',
  'place',
  'quai',
  'impasse',
  'boulevard',
  'cours',
  'sentier'
}
local RUES = {
  'Lumènes',
  'Zébrels',
  'Orchandes',
  'Brumillons',
  'Castorêts',
  'Dorimèdes',
  'Étherlins',
  'Fulgorions',
  'Glyptores',
  'Néphélins',
  'Pétrasons',
  'Volérives',
  'Aurorelles',
  'Claironnets',
  'Mésangeots',
  'Roncevoies'
}
local PARTIES = {
  'ada',
  'bob',
  'cami',
  'dan',
  'eva',
  'fifi',
  'gus',
  'hugo',
  'iris',
  'jules',
  'kate',
  'leo',
  'mira',
  'nino',
  'olive',
  'paul'
}
local _tel
_tel = function(rng)
  return "06 00 00 " .. tostring(rng.int(10, 99)) .. " " .. tostring(rng.int(10, 99))
end
local _courriel
_courriel = function(rng)
  return tostring(rng.pick(PARTIES)) .. "." .. tostring(rng.pick(PARTIES)) .. tostring(rng.int(1, 999)) .. "@exemple.invalid"
end
local _adresse
_adresse = function(rng)
  return tostring(rng.int(1, 150)) .. " " .. tostring(rng.pick(VOIES)) .. " des " .. tostring(rng.pick(RUES))
end
local _valeur
_valeur = function(rng, t)
  if t == 1 then
    return _tel(rng)
  end
  if t == 2 then
    return _courriel(rng)
  end
  return _adresse(rng)
end
local _type_for
_type_for = function(i)
  return (i - 1) % 3 + 1
end
local _links
_links = function(rng, personnes, n_coords, n_links)
  local out = { }
  if #personnes == 0 then
    return out
  end
  local owner = { }
  for c = 1, n_coords do
    local p = rng.pick(personnes)
    owner[c] = p
    table.insert(out, {
      id = #out + 1,
      personne = p,
      coordonnee = c,
      libelle = rng.pick(LIBELLES)
    })
  end
  for c = 1, n_links - n_coords do
    local _continue_0 = false
    repeat
      local p1 = owner[c]
      if not p1 then
        _continue_0 = true
        break
      end
      local others
      do
        local _accum_0 = { }
        local _len_0 = 1
        for _index_0 = 1, #personnes do
          local p = personnes[_index_0]
          if p ~= p1 then
            _accum_0[_len_0] = p
            _len_0 = _len_0 + 1
          end
        end
        others = _accum_0
      end
      if #others == 0 then
        _continue_0 = true
        break
      end
      table.insert(out, {
        id = #out + 1,
        personne = rng.pick(others),
        coordonnee = c,
        libelle = rng.pick(LIBELLES)
      })
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  return out
end
local generate
generate = function(rng, k, ecole)
  local personnes = (ecole and ecole.personnes) or { }
  local n_coords = 30 * k
  local n_links = 50 * k
  local types_rows = { }
  for i = 1, #TYPES do
    table.insert(types_rows, {
      id = i,
      type = TYPES[i]
    })
  end
  local coord_rows = { }
  for i = 1, n_coords do
    local t = _type_for(i)
    table.insert(coord_rows, {
      id = i,
      type_coordonnee = t,
      valeur = _valeur(rng, t)
    })
  end
  local links = _links(rng, personnes, n_coords, n_links)
  local tables = {
    {
      space = 'TypesCoordonnees',
      rows = types_rows
    },
    {
      space = 'Coordonnees',
      rows = coord_rows
    },
    {
      space = 'PersonnesCoordonnees',
      rows = links
    }
  }
  return {
    tables = tables
  }
end
return {
  generate = generate
}
