-- tests/test_formula_space_readonly.moon
-- Le cache par requête de space() est partagé entre toutes les évaluations
-- d'une même requête. Les lignes qu'il rend doivent donc être en LECTURE
-- SEULE : une formule qui écrit `r.prix = …` sur une ligne de space('A')
-- levait aucune erreur et modifiait le cache, contaminant les évaluations
-- suivantes (colonne calculée voisine, résolutions FK) sans trace.

R             = require 'tests.runner'
json          = require 'json'
spaces_mod    = require 'core.spaces'
formula_proxy = require 'core.formula_proxy'
data_r        = require 'resolvers.data_resolvers'

SUFFIX = tostring math.random 100000, 999999
A_NAME = "fsro_a_#{SUFFIX}"   -- espace lu par space()
B_NAME = "fsro_b_#{SUFFIX}"   -- colonne calculée qui tente de le modifier

admin_user = require('core.auth').get_user_by_username 'admin'
CTX = { user_id: admin_user.id }

ins = (space_id, data) ->
  data_r.Mutation.insertRecord nil, { spaceId: space_id, data: data }, CTX

decode_item = (item) -> if type(item.data) == 'string' then json.decode(item.data) else item.data

-- A : deux lignes, prix 10 et 20.
a_sp = spaces_mod.create_user_space A_NAME, 'fsro — espace lu par space()'
a_id = a_sp.id
spaces_mod.add_field a_id, 'prix', 'Int'
ins a_id, { prix: 10 }
ins a_id, { prix: 20 }

-- B : colonne calculée qui tente d'écrire dans une ligne de A, puis relit A.
b_sp = spaces_mod.create_user_space B_NAME, 'fsro — colonne calculée qui écrit dans space()'
b_id = b_sp.id
spaces_mod.add_field b_id, 'label', 'String'
tamper_formula = '(function() local r = space("' .. A_NAME .. '")[1]; r.prix = 999; ' ..
  'return tostring(space("' .. A_NAME .. '")[1].prix) end)()'
spaces_mod.add_field b_id, 'tamper', 'String', false, '', tamper_formula, nil, 'lua', 'self.tamper'
ins b_id, { label: 'x' }

R.describe "space() — cache par requête en lecture seule", ->

  R.it "rend des lignes en lecture seule (cache par requête)", ->
    fk_cache = { can_read: -> true }
    helper = formula_proxy.make_space_helper fk_cache
    rows = helper A_NAME
    R.eq #rows, 2, 'deux lignes'
    -- L'ordre de select n'est pas l'ordre d'insertion : on raisonne sur les
    -- valeurs, pas sur les positions.
    values = [r.prix for r in *rows]
    table.sort values
    R.eq values[1], 10, 'première valeur'
    R.eq values[2], 20, 'seconde valeur'

    before = rows[1].prix
    R.raises (-> rows[1].prix = 999), 'read%-only', "l'affectation d'un champ existant doit lever"
    R.raises (-> rows[2].nouveau = 1), 'read%-only', "l'ajout d'un champ doit lever"
    R.eq rows[1].prix, before, 'la ligne rendue reste inchangée'

    after = [r.prix for r in *helper(A_NAME)]
    table.sort after
    R.eq after[1], 10, "l'évaluation suivante doit toujours voir 10"
    R.eq after[2], 20, "l'évaluation suivante doit toujours voir 20"

  R.it "sans cache (chemin trigger), space() relit la base à chaque appel", ->
    helper = formula_proxy.make_space_helper nil
    rows = helper A_NAME
    before = rows[1].prix
    rows[1].prix = 999 -- copie locale : ne doit rien persister
    R.eq helper(A_NAME)[1].prix, before, 'aucune mémoïsation sans fk_cache'
    R.ne helper(A_NAME)[1].prix, 999, 'la valeur fabriquée ne doit pas ressortir'

  R.it "une formule qui écrit dans space('A') est signalée et ne contamine rien", ->
    res = data_r.Query.records nil, { spaceId: b_id, limit: 10 }, CTX
    R.eq res.total, 1, 'une ligne dans B'
    d = decode_item res.items[1]
    R.matches tostring(d._repr_tamper), 'read%-only',
      "la formule doit être arrêtée avec un message clair, got #{tostring d._repr_tamper}"

    -- La ligne lue n'a pas été modifiée dans le cache de la requête.
    fk_cache = CTX._fk_cache
    R.ok fk_cache and fk_cache.spaces and fk_cache.spaces[A_NAME],
      'A doit être en cache dans la requête'
    cached = fk_cache.spaces[A_NAME]
    cached_values = [r.prix for r in *cached.list]
    table.sort cached_values
    R.eq cached_values[1], 10, "le cache de la requête n'a pas été contaminé"
    R.eq cached_values[2], 20, "le cache de la requête n'a pas été contaminé (2e ligne)"

    -- Ni en base.
    t = box.space["data_#{A_NAME}"]\select {}
    prix = {}
    for tuple in *t
      table.insert prix, json.decode(tuple[2]).prix
    table.sort prix
    R.eq prix[1], 10, 'valeur stockée intacte'
    R.eq prix[2], 20, 'valeur stockée intacte (2e ligne)'

-- ── Nettoyage ────────────────────────────────────────────────────────────────

spaces_mod.delete_user_space B_NAME
spaces_mod.delete_user_space A_NAME
require('resolvers.init').reinit!
