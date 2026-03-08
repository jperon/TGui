-- resolvers/utils.moon
-- Utilitaires partagés par tous les resolvers.

-- Vérifie qu'un contexte d'authentification est présent.
-- Lève une erreur GraphQL "Unauthorized" sinon.
require_auth = (ctx) ->
  error "Unauthorized" unless ctx and ctx.user_id
  ctx.user_id

-- Vérifie que l'utilisateur connecté est membre du groupe 'admin'.
-- On fait une recherche par nom de groupe plutôt que par id (plus robuste).
require_admin = (ctx) ->
  uid = require_auth ctx
  is_admin = false
  for gid_row in *box.space._tdb_memberships.index.by_user\select { uid }
    g = box.space._tdb_groups\get gid_row[2]
    if g and g[2] == 'admin'
      is_admin = true
      break
  error "Forbidden" unless is_admin
  uid

{ :require_auth, :require_admin }
