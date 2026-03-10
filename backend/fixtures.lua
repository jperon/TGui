local log = require('log')
local spaces = require('core.spaces')
local auth = require('core.auth')
local insert_data
insert_data = function(space_name, data)
  local json_data = require('json').encode(data)
  local space = box.space[space_name]
  local new_id = space.sequence["_tdb_seq_id"]:next()
  space:insert({
    new_id,
    json_data
  })
  return log.info("Inserted data with auto-generated id " .. tostring(new_id) .. " into " .. tostring(space_name))
end
local setup_demo_data
setup_demo_data = function()
  local existing_spaces = spaces.list_spaces()
  if #existing_spaces > 0 then
    return 
  end
  log.info("Setting up demo data for test environment...")
  local authors_space = spaces.create_user_space('Auteurs', 'Catalogue des auteurs')
  spaces.add_field(authors_space.id, 'particule', 'String', false, 'Particule du nom (de, du, etc.)')
  spaces.add_field(authors_space.id, 'nom', 'String', true, 'Nom de famille')
  spaces.add_field(authors_space.id, 'prenom', 'String', false, 'Prénom')
  spaces.add_field(authors_space.id, 'nom_complet', 'String', false, '', 'self.prenom and self.nom and (self.prenom .. " " .. self.nom) or (self.nom or "")', nil, 'lua', 'self.prenom and self.nom and (self.prenom .. " " .. self.nom) or (self.nom or "")')
  spaces.add_field(authors_space.id, 'biographie', 'String', false, 'Courte biographie')
  spaces.add_field(authors_space.id, 'date_naissance', 'Datetime', false, 'Date de naissance')
  spaces.add_field(authors_space.id, 'nationalite', 'String', false, 'Nationalité')
  local books_space = spaces.create_user_space('Livres', 'Catalogue des livres')
  spaces.add_field(books_space.id, 'titre', 'String', true, 'Titre du livre')
  spaces.add_field(books_space.id, 'isbn', 'String', false, 'ISBN')
  spaces.add_field(books_space.id, 'annee_publication', 'Int', false, 'Année de publication')
  spaces.add_field(books_space.id, 'genre', 'String', false, 'Genre littéraire')
  spaces.add_field(books_space.id, 'pages', 'Int', false, 'Nombre de pages')
  spaces.add_field(books_space.id, 'disponible', 'Boolean', false, 'Disponible à l\'emprunt')
  spaces.add_field(books_space.id, 'prix', 'Float', false, 'Prix en euros')
  spaces.add_field(books_space.id, 'couverture', 'String', false, '', 'self.titre and "📚 " .. string.sub(self.titre, 1, 20) .. (string.len(self.titre) > 20 and "..." or "")', nil, 'lua', 'self.titre and "📚 " .. string.sub(self.titre, 1, 20) .. (string.len(self.titre) > 20 and "..." or "")')
  local loans_space = spaces.create_user_space('Emprunts', 'Gestion des emprunts')
  spaces.add_field(loans_space.id, 'livre_id', 'String', true, 'ID du livre emprunté')
  spaces.add_field(loans_space.id, 'emprunteur_nom', 'String', true, 'Nom de l\'emprunteur')
  spaces.add_field(loans_space.id, 'date_emprunt', 'Datetime', true, 'Date d\'emprunt')
  spaces.add_field(loans_space.id, 'date_retour_prevue', 'Datetime', false, 'Date de retour prévue')
  spaces.add_field(loans_space.id, 'date_retour_effective', 'Datetime', false, 'Date de retour effective')
  spaces.add_field(loans_space.id, 'statut', 'String', false, '', 'self.date_retour_effective and "Rendu" or (self.date_retour_prevue and os.time() > self.date_retour_prevue and "En retard" or "En cours") or "En cours"', nil, 'lua', 'self.date_retour_effective and "✅ " .. (self.date_retour_effective and os.date("%d/%m/%Y", self.date_retour_effective) or "") or (self.date_retour_prevue and os.time() > self.date_retour_prevue and "⚠️ En retard" or "📖 En cours") or "📖 En cours"')
  local categories_space = spaces.create_user_space('Categories', 'Catégories de livres')
  spaces.add_field(categories_space.id, 'nom', 'String', true, 'Nom de la catégorie')
  spaces.add_field(categories_space.id, 'description', 'String', false, 'Description')
  spaces.add_field(categories_space.id, 'couleur', 'String', false, 'Code couleur hexadecimal')
  spaces.add_field(categories_space.id, 'parent_id', 'String', false, 'Catégorie parente')
  spaces.add_field(categories_space.id, 'ordre', 'Int', false, 'Ordre d\'affichage')
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
    },
    {
      particule = "",
      nom = "Sartre",
      prenom = "Jean-Paul",
      biographie = "Écrivain et philosophe français",
      nationalite = "Française"
    },
    {
      particule = "",
      nom = "Simenon",
      prenom = "Georges",
      biographie = "Écrivain belge, créateur du commissaire Maigret",
      nationalite = "Belge"
    },
    {
      particule = "",
      nom = "Colette",
      prenom = "Sidonie Gabrielle",
      biographie = "Femme de lettres française",
      nationalite = "Française"
    },
    {
      particule = "d'Annunzio",
      nom = "Gabriele",
      prenom = "",
      biographie = "Écrivain et poète italien",
      nationalite = "Italienne"
    },
    {
      particule = "",
      nom = "Kafka",
      prenom = "Franz",
      biographie = "Écrivain tchèque de langue allemande",
      nationalite = "Tchèque"
    }
  }
  for _index_0 = 1, #authors_data do
    local author = authors_data[_index_0]
    insert_data("data_" .. tostring(authors_space.name), author)
  end
  local books_data = {
    {
      titre = "Les Misérables",
      isbn = "978-2-253-05407-5",
      annee_publication = 1862,
      genre = "Roman historique",
      pages = 1232,
      disponible = true,
      prix = 12.99
    },
    {
      titre = "Bel-Ami",
      isbn = "978-2-07-036418-8",
      annee_publication = 1885,
      genre = "Roman réaliste",
      pages = 432,
      disponible = true,
      prix = 9.99
    },
    {
      titre = "L'Étranger",
      isbn = "978-2-07-040200-7",
      annee_publication = 1942,
      genre = "Roman existentialiste",
      pages = 185,
      disponible = false,
      prix = 7.50
    },
    {
      titre = "Du côté de chez Swann",
      isbn = "978-2-07-041424-7",
      annee_publication = 1913,
      genre = "Roman",
      pages = 512,
      disponible = true,
      prix = 11.99
    },
    {
      titre = "Fables",
      isbn = "978-2-07-038934-7",
      annee_publication = 1668,
      genre = "Poésie",
      pages = 320,
      disponible = true,
      prix = 8.50
    },
    {
      titre = "La Nausée",
      isbn = "978-2-07-036003-4",
      annee_publication = 1938,
      genre = "Roman philosophique",
      pages = 256,
      disponible = true,
      prix = 9.25
    },
    {
      titre = "Pierre et Jean",
      isbn = "978-2-07-041112-7",
      annee_publication = 1888,
      genre = "Roman psychologique",
      pages = 284,
      disponible = false,
      prix = 8.99
    },
    {
      titre = "La Condition humaine",
      isbn = "978-2-07-036939-7",
      annee_publication = 1933,
      genre = "Roman",
      pages = 688,
      disponible = true,
      prix = 13.50
    },
    {
      titre = "Le Procès",
      isbn = "978-2-07-041631-3",
      annee_publication = 1925,
      genre = "Roman",
      pages = 312,
      disponible = true,
      prix = 10.25
    },
    {
      titre = "Germinal",
      isbn = "978-2-253-05416-9",
      annee_publication = 1885,
      genre = "Roman naturaliste",
      pages = 598,
      disponible = false,
      prix = 11.75
    },
    {
      titre = "Madame Bovary",
      isbn = "978-2-07-040821-6",
      annee_publication = 1857,
      genre = "Roman réaliste",
      pages = 428,
      disponible = true,
      prix = 9.99
    },
    {
      titre = "Le Grand Meaulnes",
      isbn = "978-2-07-040962-6",
      annee_publication = 1913,
      genre = "Roman",
      pages = 384,
      disponible = true,
      prix = 8.75
    }
  }
  for _index_0 = 1, #books_data do
    local book = books_data[_index_0]
    insert_data("data_" .. tostring(books_space.name), book)
  end
  local categories_data = {
    {
      nom = "Littérature française",
      description = "Œuvres d'auteurs français",
      couleur = "#FF6B6B",
      parent_id = "",
      ordre = 1
    },
    {
      nom = "Littérature étrangère",
      description = "Œuvres traduites",
      couleur = "#4ECDC4",
      parent_id = "",
      ordre = 2
    },
    {
      nom = "Classiques",
      description = "Œuvres classiques",
      couleur = "#45B7D1",
      parent_id = "1",
      ordre = 1
    },
    {
      nom = "XXe siècle",
      description = "Littérature moderne",
      couleur = "#96CEB4",
      parent_id = "1",
      ordre = 2
    },
    {
      nom = "Philosophie",
      description = "Essais philosophiques",
      couleur = "#FFEAA7",
      parent_id = "1",
      ordre = 3
    },
    {
      nom = "Science-fiction",
      description = "Romans de science-fiction",
      couleur = "#DDA0DD",
      parent_id = "2",
      ordre = 1
    },
    {
      nom = "Polar",
      description = "Romans policiers",
      couleur = "#F4A460",
      parent_id = "2",
      ordre = 2
    }
  }
  for _index_0 = 1, #categories_data do
    local category = categories_data[_index_0]
    insert_data("data_" .. tostring(categories_space.name), category)
  end
  local current_time = os.time()
  local loans_data = {
    {
      livre_id = "1",
      emprunteur_nom = "Alice Martin",
      date_emprunt = current_time - 86400 * 7,
      date_retour_prevue = current_time + 86400 * 7,
      date_retour_effective = nil
    },
    {
      livre_id = "3",
      emprunteur_nom = "Bob Dubois",
      date_emprunt = current_time - 86400 * 14,
      date_retour_prevue = current_time - 86400 * 2,
      date_retour_effective = current_time - 86400
    },
    {
      livre_id = "5",
      emprunteur_nom = "Claire Petit",
      date_emprunt = current_time - 86400 * 3,
      date_retour_prevue = current_time + 86400 * 11,
      date_retour_effective = nil
    },
    {
      livre_id = "8",
      emprunteur_nom = "David Leroy",
      date_emprunt = current_time - 86400 * 21,
      date_retour_prevue = current_time - 86400 * 5,
      date_retour_effective = nil
    },
    {
      livre_id = "10",
      emprunteur_nom = "Emma Bernard",
      date_emprunt = current_time - 86400 * 1,
      date_retour_prevue = current_time + 86400 * 14,
      date_retour_effective = nil
    }
  }
  for _index_0 = 1, #loans_data do
    local loan = loans_data[_index_0]
    insert_data("data_" .. tostring(loans_space.name), loan)
  end
  return log.info("Demo data setup complete. Created 4 spaces with sample data.")
end
if os.getenv("TGUI_TEST_ENV") == "true" then
  setup_demo_data()
end
return {
  setup_demo_data = setup_demo_data
}
