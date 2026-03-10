-- backend/fixtures.moon
-- Jeu de données factices pour le conteneur de test TGui
-- Exécuté automatiquement au démarrage du conteneur de test

log = require 'log'
spaces = require 'core.spaces'
auth = require 'core.auth'

-- Crée des données de démonstration seulement si la base est vide
setup_demo_data = ->
  -- Vérifier s'il y a déjà des espaces utilisateur
  existing_spaces = spaces.list_spaces!
  return if #existing_spaces > 0
  
  log.info "Setting up demo data for test environment..."
  
  -- ── Espaces de démonstration ────────────────────────────────────────
  
  -- Espace: Auteurs
  authors_space = spaces.create_user_space 'Auteurs', 'Catalogue des auteurs'
  
  -- Champs pour Auteurs
  spaces.add_field authors_space.id, 'particule', 'String', false, 'Particule du nom (de, du, etc.)'
  spaces.add_field authors_space.id, 'nom', 'String', true, 'Nom de famille'
  spaces.add_field authors_space.id, 'prenom', 'String', false, 'Prénom'
  spaces.add_field authors_space.id, 'nom_complet', 'String', false, '', 
    'self.prenom and self.nom and (self.prenom .. " " .. self.nom) or (self.nom or "")', 
    nil, 'lua', 
    'self.prenom and self.nom and (self.prenom .. " " .. self.nom) or (self.nom or "")'
  spaces.add_field authors_space.id, 'biographie', 'String', false, 'Courte biographie'
  spaces.add_field authors_space.id, 'date_naissance', 'Datetime', false, 'Date de naissance'
  spaces.add_field authors_space.id, 'nationalite', 'String', false, 'Nationalité'
  
  -- Espace: Livres
  books_space = spaces.create_user_space 'Livres', 'Catalogue des livres'
  
  -- Champs pour Livres
  spaces.add_field books_space.id, 'titre', 'String', true, 'Titre du livre'
  spaces.add_field books_space.id, 'isbn', 'String', false, 'ISBN'
  spaces.add_field books_space.id, 'annee_publication', 'Int', false, 'Année de publication'
  spaces.add_field books_space.id, 'genre', 'String', false, 'Genre littéraire'
  spaces.add_field books_space.id, 'pages', 'Int', false, 'Nombre de pages'
  spaces.add_field books_space.id, 'disponible', 'Boolean', false, 'Disponible à l\'emprunt'
  spaces.add_field books_space.id, 'prix', 'Float', false, 'Prix en euros'
  spaces.add_field books_space.id, 'couverture', 'String', false, '', 
    'self.titre and "📚 " .. string.sub(self.titre, 1, 20) .. (string.len(self.titre) > 20 and "..." or "")', 
    nil, 'lua',
    'self.titre and "📚 " .. string.sub(self.titre, 1, 20) .. (string.len(self.titre) > 20 and "..." or "")'
  
  -- Espace: Emprunts
  loans_space = spaces.create_user_space 'Emprunts', 'Gestion des emprunts'
  
  -- Champs pour Emprunts
  spaces.add_field loans_space.id, 'livre_id', 'String', true, 'ID du livre emprunté'
  spaces.add_field loans_space.id, 'emprunteur_nom', 'String', true, 'Nom de l\'emprunteur'
  spaces.add_field loans_space.id, 'date_emprunt', 'Datetime', true, 'Date d\'emprunt'
  spaces.add_field loans_space.id, 'date_retour_prevue', 'Datetime', false, 'Date de retour prévue'
  spaces.add_field loans_space.id, 'date_retour_effective', 'Datetime', false, 'Date de retour effective'
  spaces.add_field loans_space.id, 'statut', 'String', false, '', 
    'self.date_retour_effective and "Rendu" or (self.date_retour_prevue and os.time() > self.date_retour_prevue and "En retard" or "En cours") or "En cours"', 
    nil, 'lua',
    'self.date_retour_effective and "✅ " .. (self.date_retour_effective and os.date("%d/%m/%Y", self.date_retour_effective) or "") or (self.date_retour_prevue and os.time() > self.date_retour_prevue and "⚠️ En retard" or "📖 En cours") or "📖 En cours"'
  
  -- Espace: Catégories
  categories_space = spaces.create_user_space 'Categories', 'Catégories de livres'
  
  -- Champs pour Catégories
  spaces.add_field categories_space.id, 'nom', 'String', true, 'Nom de la catégorie'
  spaces.add_field categories_space.id, 'description', 'String', false, 'Description'
  spaces.add_field categories_space.id, 'couleur', 'String', false, 'Code couleur hexadecimal'
  spaces.add_field categories_space.id, 'parent_id', 'String', false, 'Catégorie parente'
  spaces.add_field categories_space.id, 'ordre', 'Int', false, 'Ordre d\'affichage'
  
  -- ── Insertion des données ────────────────────────────────────────────
  
  -- Données pour Auteurs
  authors_data = {
    { id: "1", particule: "", nom: "Hugo", prenom: "Victor", biographie: "Écrivain, poète et dramaturge français", nationalite: "Française" }
    { id: "2", particule: "de", nom: "Maupassant", prenom: "Guy", biographie: "Écrivain et journaliste français", nationalite: "Française" }
    { id: "3", particule: "", nom: "Camus", prenom: "Albert", biographie: "Écrivain, philosophe et journaliste français", nationalite: "Française" }
    { id: "4", particule: "", nom: "Proust", prenom: "Marcel", biographie: "Écrivain français", nationalite: "Française" }
    { id: "5", particule: "de", nom: "La Fontaine", prenom: "Jean", biographie: "Poète français, célèbre pour ses fables", nationalite: "Française" }
    { id: "6", particule: "", nom: "Sartre", prenom: "Jean-Paul", biographie: "Écrivain et philosophe français", nationalite: "Française" }
    { id: "7", particule: "", nom: "Simenon", prenom: "Georges", biographie: "Écrivain belge, créateur du commissaire Maigret", nationalite: "Belge" }
    { id: "8", particule: "", nom: "Colette", prenom: "Sidonie Gabrielle", biographie: "Femme de lettres française", nationalite: "Française" }
    { id: "9", particule: "d'Annunzio", nom: "Gabriele", prenom: "", biographie: "Écrivain et poète italien", nationalite: "Italienne" }
    { id: "10", particule: "", nom: "Kafka", prenom: "Franz", biographie: "Écrivain tchèque de langue allemande", nationalite: "Tchèque" }
  }
  
  for author in *authors_data
    json_data = require('json').encode(author)
    box.space["data_#{authors_space.name}"]\insert { author.id, json_data }
  
  -- Données pour Livres
  books_data = {
    { id: "1", titre: "Les Misérables", isbn: "978-2-253-05407-5", annee_publication: 1862, genre: "Roman historique", pages: 1232, disponible: true, prix: 12.99 }
    { id: "2", titre: "Bel-Ami", isbn: "978-2-07-036418-8", annee_publication: 1885, genre: "Roman réaliste", pages: 432, disponible: true, prix: 9.99 }
    { id: "3", titre: "L'Étranger", isbn: "978-2-07-040200-7", annee_publication: 1942, genre: "Roman existentialiste", pages: 185, disponible: false, prix: 7.50 }
    { id: "4", titre: "Du côté de chez Swann", isbn: "978-2-07-041424-7", annee_publication: 1913, genre: "Roman", pages: 512, disponible: true, prix: 11.99 }
    { id: "5", titre: "Fables", isbn: "978-2-07-038934-7", annee_publication: 1668, genre: "Poésie", pages: 320, disponible: true, prix: 8.50 }
    { id: "6", titre: "La Nausée", isbn: "978-2-07-036003-4", annee_publication: 1938, genre: "Roman philosophique", pages: 256, disponible: true, prix: 9.25 }
    { id: "7", titre: "Pierre et Jean", isbn: "978-2-07-041112-7", annee_publication: 1888, genre: "Roman psychologique", pages: 284, disponible: false, prix: 8.99 }
    { id: "8", titre: "La Condition humaine", isbn: "978-2-07-036939-7", annee_publication: 1933, genre: "Roman", pages: 688, disponible: true, prix: 13.50 }
    { id: "9", titre: "Le Procès", isbn: "978-2-07-041631-3", annee_publication: 1925, genre: "Roman", pages: 312, disponible: true, prix: 10.25 }
    { id: "10", titre: "Germinal", isbn: "978-2-253-05416-9", annee_publication: 1885, genre: "Roman naturaliste", pages: 598, disponible: false, prix: 11.75 }
    { id: "11", titre: "Madame Bovary", isbn: "978-2-07-040821-6", annee_publication: 1857, genre: "Roman réaliste", pages: 428, disponible: true, prix: 9.99 }
    { id: "12", titre: "Le Grand Meaulnes", isbn: "978-2-07-040962-6", annee_publication: 1913, genre: "Roman", pages: 384, disponible: true, prix: 8.75 }
  }
  
  for book in *books_data
    json_data = require('json').encode(book)
    box.space["data_#{books_space.name}"]\insert { book.id, json_data }
  
  -- Données pour Catégories
  categories_data = {
    { id: "1", nom: "Littérature française", description: "Œuvres d'auteurs français", couleur: "#FF6B6B", parent_id: "", ordre: 1 }
    { id: "2", nom: "Littérature étrangère", description: "Œuvres traduites", couleur: "#4ECDC4", parent_id: "", ordre: 2 }
    { id: "3", nom: "Classiques", description: "Œuvres classiques", couleur: "#45B7D1", parent_id: "1", ordre: 1 }
    { id: "4", nom: "XXe siècle", description: "Littérature moderne", couleur: "#96CEB4", parent_id: "1", ordre: 2 }
    { id: "5", nom: "Philosophie", description: "Essais philosophiques", couleur: "#FFEAA7", parent_id: "1", ordre: 3 }
    { id: "6", nom: "Science-fiction", description: "Romans de science-fiction", couleur: "#DDA0DD", parent_id: "2", ordre: 1 }
    { id: "7", nom: "Polar", description: "Romans policiers", couleur: "#F4A460", parent_id: "2", ordre: 2 }
  }
  
  for category in *categories_data
    json_data = require('json').encode(category)
    box.space["data_#{categories_space.name}"]\insert { category.id, json_data }
  
  -- Données pour Emprunts
  current_time = os.time()
  loans_data = {
    { id: "1", livre_id: "1", emprunteur_nom: "Alice Martin", date_emprunt: current_time - 86400 * 7, date_retour_prevue: current_time + 86400 * 7, date_retour_effective: nil }
    { id: "2", livre_id: "3", emprunteur_nom: "Bob Dubois", date_emprunt: current_time - 86400 * 14, date_retour_prevue: current_time - 86400 * 2, date_retour_effective: current_time - 86400 }
    { id: "3", livre_id: "5", emprunteur_nom: "Claire Petit", date_emprunt: current_time - 86400 * 3, date_retour_prevue: current_time + 86400 * 11, date_retour_effective: nil }
    { id: "4", livre_id: "8", emprunteur_nom: "David Leroy", date_emprunt: current_time - 86400 * 21, date_retour_prevue: current_time - 86400 * 5, date_retour_effective: nil }
    { id: "5", livre_id: "10", emprunteur_nom: "Emma Bernard", date_emprunt: current_time - 86400 * 1, date_retour_prevue: current_time + 86400 * 14, date_retour_effective: nil }
  }
  
  for loan in *loans_data
    json_data = require('json').encode(loan)
    box.space["data_#{loans_space.name}"]\insert { loan.id, json_data }
  
  log.info "Demo data setup complete. Created 4 spaces with sample data."

-- Exécuter le setup si on est en environnement de test
if os.getenv("TGUI_TEST_ENV") == "true"
  setup_demo_data!

{ :setup_demo_data }
