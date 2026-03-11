local log = require('log')
local spaces = require('core.spaces')
local auth = require('core.auth')
local executor = require('graphql.executor')
local execute_mutation
execute_mutation = function(mutation, variables)
  local admin_user = {
    id = 1,
    username = "admin"
  }
  local context = {
    user_id = admin_user.id
  }
  local result = executor.execute({
    query = mutation,
    variables = variables,
    context = context
  })
  if result.errors then
    error("GraphQL mutation failed: " .. tostring(require('json').encode(result.errors)))
  end
  return result.data
end
local setup_demo_data
setup_demo_data = function()
  local all_spaces = spaces.list_spaces()
  local user_spaces
  do
    local _accum_0 = { }
    local _len_0 = 1
    for _index_0 = 1, #all_spaces do
      local space = all_spaces[_index_0]
      if not space.name:match('^_tdb_') then
        _accum_0[_len_0] = space
        _len_0 = _len_0 + 1
      end
    end
    user_spaces = _accum_0
  end
  if #user_spaces > 0 then
    return 
  end
  log.info("Setting up demo data for test environment...")
  local authors_result = execute_mutation([[    mutation { createSpace(input: { name: "Auteurs", description: "Catalogue des auteurs" }) { id name } }
  ]], { })
  local authors_space_id = authors_result.createSpace.id
  execute_mutation([[    mutation AddAuthorsFields($spaceId: ID!) {
      f1: addField(spaceId: $spaceId, input: { name: "particule", fieldType: String, description: "Particule du nom (de, du, etc.)" }) { id }
      f2: addField(spaceId: $spaceId, input: { name: "nom", fieldType: String, notNull: true, description: "Nom de famille" }) { id }
      f3: addField(spaceId: $spaceId, input: { name: "prenom", fieldType: String, description: "Prénom" }) { id }
      f4: addField(spaceId: $spaceId, input: { name: "biographie", fieldType: String, description: "Courte biographie" }) { id }
      f5: addField(spaceId: $spaceId, input: { name: "date_naissance", fieldType: Datetime, description: "Date de naissance" }) { id }
      f6: addField(spaceId: $spaceId, input: { name: "nationalite", fieldType: String, description: "Nationalité" }) { id }
    }
  ]], {
    spaceId = authors_space_id
  })
  local books_result = execute_mutation([[    mutation { createSpace(input: { name: "Livres", description: "Catalogue des livres" }) { id name } }
  ]], { })
  local books_space_id = books_result.createSpace.id
  execute_mutation([[    mutation AddBooksFields($spaceId: ID!) {
      f1: addField(spaceId: $spaceId, input: { name: "titre", fieldType: String, notNull: true, description: "Titre du livre" }) { id }
      f2: addField(spaceId: $spaceId, input: { name: "isbn", fieldType: String, description: "ISBN" }) { id }
      f3: addField(spaceId: $spaceId, input: { name: "annee_publication", fieldType: Int, description: "Année de publication" }) { id }
      f4: addField(spaceId: $spaceId, input: { name: "genre", fieldType: String, description: "Genre littéraire" }) { id }
      f5: addField(spaceId: $spaceId, input: { name: "pages", fieldType: Int, description: "Nombre de pages" }) { id }
      f6: addField(spaceId: $spaceId, input: { name: "disponible", fieldType: Boolean, description: "Disponible à l'emprunt" }) { id }
      f7: addField(spaceId: $spaceId, input: { name: "prix", fieldType: Float, description: "Prix en euros" }) { id }
      f8: addField(spaceId: $spaceId, input: { name: "auteur", fieldType: Int, description: "Auteur du livre" }) { id }
    }
  ]], {
    spaceId = books_space_id
  })
  local loans_result = execute_mutation([[    mutation { createSpace(input: { name: "Emprunts", description: "Gestion des emprunts" }) { id name } }
  ]], { })
  local loans_space_id = loans_result.createSpace.id
  execute_mutation([[    mutation AddLoansFields($spaceId: ID!) {
      f1: addField(spaceId: $spaceId, input: { name: "livre", fieldType: Int, notNull: true, description: "Livre emprunté" }) { id }
      f2: addField(spaceId: $spaceId, input: { name: "emprunteur_nom", fieldType: String, notNull: true, description: "Nom de l'emprunteur" }) { id }
      f3: addField(spaceId: $spaceId, input: { name: "date_emprunt", fieldType: Datetime, notNull: true, description: "Date d'emprunt" }) { id }
      f4: addField(spaceId: $spaceId, input: { name: "date_retour_prevue", fieldType: Datetime, description: "Date de retour prévue" }) { id }
      f5: addField(spaceId: $spaceId, input: { name: "date_retour_effective", fieldType: Datetime, description: "Date de retour effective" }) { id }
    }
  ]], {
    spaceId = loans_space_id
  })
  local categories_result = execute_mutation([[    mutation { createSpace(input: { name: "Categories", description: "Catégories de livres" }) { id name } }
  ]], { })
  local categories_space_id = categories_result.createSpace.id
  execute_mutation([[    mutation AddCategoriesFields($spaceId: ID!) {
      f1: addField(spaceId: $spaceId, input: { name: "nom", fieldType: String, notNull: true, description: "Nom de la catégorie" }) { id }
      f2: addField(spaceId: $spaceId, input: { name: "description", fieldType: String, description: "Description" }) { id }
      f3: addField(spaceId: $spaceId, input: { name: "couleur", fieldType: String, description: "Code couleur hexadecimal" }) { id }
      f4: addField(spaceId: $spaceId, input: { name: "parent", fieldType: Int, description: "Catégorie parente" }) { id }
      f5: addField(spaceId: $spaceId, input: { name: "ordre", fieldType: Int, description: "Ordre d'affichage" }) { id }
    }
  ]], {
    spaceId = categories_space_id
  })
  local authors_data = {
    {
      particule = "",
      nom = "Hugo",
      prenom = "Victor",
      biographie = "Écrivain, poète et dramaturge français",
      nationalite = "Française"
    },
    {
      particule = "de",
      nom = "Maupassant",
      prenom = "Guy",
      biographie = "Écrivain et journaliste français",
      nationalite = "Française"
    },
    {
      particule = "",
      nom = "Camus",
      prenom = "Albert",
      biographie = "Écrivain, philosophe et journaliste français",
      nationalite = "Française"
    },
    {
      particule = "",
      nom = "Proust",
      prenom = "Marcel",
      biographie = "Écrivain français",
      nationalite = "Française"
    },
    {
      particule = "de",
      nom = "La Fontaine",
      prenom = "Jean",
      biographie = "Poète français, célèbre pour ses fables",
      nationalite = "Française"
    }
  }
  execute_mutation([[    mutation InsertAuthors($spaceId: ID!, $data: [JSON!]!) {
      insertRecords(spaceId: $spaceId, data: $data) { id }
    }
  ]], {
    spaceId = authors_space_id,
    data = authors_data
  })
  local books_data = {
    {
      titre = "Les Misérables",
      isbn = "978-2-253-05407-5",
      annee_publication = 1862,
      genre = "Roman historique",
      pages = 1232,
      disponible = true,
      prix = 12.99,
      auteur = "1"
    },
    {
      titre = "Bel-Ami",
      isbn = "978-2-07-036418-8",
      annee_publication = 1885,
      genre = "Roman réaliste",
      pages = 432,
      disponible = true,
      prix = 9.99,
      auteur = "2"
    },
    {
      titre = "L'Étranger",
      isbn = "978-2-07-040200-7",
      annee_publication = 1942,
      genre = "Roman existentialiste",
      pages = 185,
      disponible = false,
      prix = 7.50,
      auteur = "3"
    },
    {
      titre = "Du côté de chez Swann",
      isbn = "978-2-07-041424-7",
      annee_publication = 1913,
      genre = "Roman",
      pages = 512,
      disponible = true,
      prix = 11.99,
      auteur = "4"
    },
    {
      titre = "Fables",
      isbn = "978-2-07-038934-7",
      annee_publication = 1668,
      genre = "Poésie",
      pages = 320,
      disponible = true,
      prix = 8.50,
      auteur = "5"
    }
  }
  execute_mutation([[    mutation InsertBooks($spaceId: ID!, $data: [JSON!]!) {
      insertRecords(spaceId: $spaceId, data: $data) { id }
    }
  ]], {
    spaceId = books_space_id,
    data = books_data
  })
  local categories_data = {
    {
      nom = "Littérature française",
      description = "Œuvres d'auteurs français",
      couleur = "#FF6B6B",
      parent = "",
      ordre = 1
    },
    {
      nom = "Littérature étrangère",
      description = "Œuvres traduites",
      couleur = "#4ECDC4",
      parent = "",
      ordre = 2
    },
    {
      nom = "Classiques",
      description = "Œuvres classiques",
      couleur = "#45B7D1",
      parent = "1",
      ordre = 1
    },
    {
      nom = "XXe siècle",
      description = "Littérature moderne",
      couleur = "#96CEB4",
      parent = "1",
      ordre = 2
    }
  }
  execute_mutation([[    mutation InsertCategories($spaceId: ID!, $data: [JSON!]!) {
      insertRecords(spaceId: $spaceId, data: $data) { id }
    }
  ]], {
    spaceId = categories_space_id,
    data = categories_data
  })
  local current_time = os.time()
  local loans_data = {
    {
      livre = "1",
      emprunteur_nom = "Alice Martin",
      date_emprunt = current_time - 86400 * 7,
      date_retour_prevue = current_time + 86400 * 7,
      date_retour_effective = nil
    },
    {
      livre = "3",
      emprunteur_nom = "Bob Dubois",
      date_emprunt = current_time - 86400 * 14,
      date_retour_prevue = current_time - 86400 * 2,
      date_retour_effective = current_time - 86400
    },
    {
      livre = "5",
      emprunteur_nom = "Claire Petit",
      date_emprunt = current_time - 86400 * 3,
      date_retour_prevue = current_time + 86400 * 11,
      date_retour_effective = nil
    }
  }
  execute_mutation([[    mutation InsertLoans($spaceId: ID!, $data: [JSON!]!) {
      insertRecords(spaceId: $spaceId, data: $data) { id }
    }
  ]], {
    spaceId = loans_space_id,
    data = loans_data
  })
  local books_fields = execute_mutation([[    mutation {
      space(id: $spaceId) {
        fields { id name }
      }
    }
  ]], {
    spaceId = books_space_id
  })
  local authors_fields = execute_mutation([[    mutation {
      space(id: $spaceId) {
        fields { id name }
      }
    }
  ]], {
    spaceId = authors_space_id
  })
  local loans_fields = execute_mutation([[    mutation {
      space(id: $spaceId) {
        fields { id name }
      }
    }
  ]], {
    spaceId = loans_space_id
  })
  local categories_fields = execute_mutation([[    mutation {
      space(id: $spaceId) {
        fields { id name }
      }
    }
  ]], {
    spaceId = categories_space_id
  })
  local get_field_id
  get_field_id = function(fields, name)
    if not fields or not fields.data or not fields.data.space or not fields.data.space.fields then
      log.warn("Failed to get fields for space: " .. tostring(name))
      return nil
    end
    for field in fields.data.space.fields do
      if field.name == name then
        return field.id
      end
    end
    return nil
  end
  local auteur_field_id = get_field_id(books_fields, "auteur")
  local authors_id_field = get_field_id(authors_fields, "id")
  if auteur_field_id and authors_id_field then
    execute_mutation([[      mutation CreateBookAuthorRelation($input: CreateRelationInput!) {
        createRelation(input: $input) { id name }
      }
    ]], {
      input = {
        name = "livre_auteur",
        fromSpaceId = books_space_id,
        fromFieldId = auteur_field_id,
        toSpaceId = authors_space_id,
        toFieldId = authors_id_field,
        reprFormula = tostring(self.nom) .. " " .. tostring(self.prenom)
      }
    })
  end
  local livre_field_id = get_field_id(loans_fields, "livre")
  local books_id_field = get_field_id(books_fields, "id")
  if livre_field_id and books_id_field then
    execute_mutation([[      mutation CreateLoanBookRelation($input: CreateRelationInput!) {
        createRelation(input: $input) { id name }
      }
    ]], {
      input = {
        name = "emprunt_livre",
        fromSpaceId = loans_space_id,
        fromFieldId = livre_field_id,
        toSpaceId = books_space_id,
        toFieldId = books_id_field,
        reprFormula = tostring(self.titre)
      }
    })
  end
  local parent_field_id = get_field_id(categories_fields, "parent")
  local categories_id_field = get_field_id(categories_fields, "id")
  if parent_field_id and categories_id_field then
    execute_mutation([[      mutation CreateCategoryParentRelation($input: CreateRelationInput!) {
        createRelation(input: $input) { id name }
      }
    ]], {
      input = {
        name = "categorie_parente",
        fromSpaceId = categories_space_id,
        fromFieldId = parent_field_id,
        toSpaceId = categories_space_id,
        toFieldId = categories_id_field,
        reprFormula = tostring(self.nom)
      }
    })
  end
  return log.info("Demo data setup complete. Created 4 spaces with sample data and 3 relations.")
end
return {
  setup_demo_data = setup_demo_data
}
