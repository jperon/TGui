// Global setup for Playwright tests — runs once before all suites.
// Ramène l'instance de test à une base déterministe : seuls les espaces de
// l'application Bibliothèque subsistent, et aucune vue / data view. Ainsi les
// suites ne s'appuient pas sur des données accumulées par des exécutions
// précédentes (isolation).

const BASE = 'http://localhost:8081';
// Espaces de l'application Bibliothèque, dans l'ordre des fichiers de structure
// ecole.yaml, bibliotheque.yaml, coordonnees.yaml (backend/apps/bibliotheque).
const DEMO_SPACES = [
  'Titres', 'Sections', 'Annee', 'Niveaux', 'Personnes', 'Prefectures',
  'Classes', 'ClassesEleves', 'Genres', 'Auteurs', 'MotsCles', 'Livres',
  'LivresMotsCles', 'Exemplaires', 'Emprunts', 'TypesCoordonnees',
  'Coordonnees', 'PersonnesCoordonnees',
];

async function gql(query, token) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers['Authorization'] = `Bearer ${token}`;
  const r = await fetch(`${BASE}/graphql`, {
    method: 'POST', headers, body: JSON.stringify({ query }),
  });
  return r.json();
}

module.exports = async function(config) {
  console.log('🚀 Playwright setup: vérification de TGui (port 8081)...');
  try {
    const response = await fetch(BASE);
    if (!response.ok) throw new Error(`TGui not responding: ${response.status}`);
    console.log('✅ TGui accessible sur le port 8081');
  } catch (error) {
    console.error('❌ TGui setup failed:', error.message);
    console.error('💡 Lance l’instance de test : make test-up');
    process.exit(1);
  }

  console.log('🧹 Réinitialisation de la base de test (baseline Bibliothèque)...');
  try {
    const login = await gql('mutation { login(username:"admin", password:"adminadmin") { token } }');
    const token = login?.data?.login?.token;
    if (!token) throw new Error('login échoué: ' + JSON.stringify(login));

    // Supprime toutes les data views et custom views
    const dvs = (await gql('{ dataViews { id } }', token))?.data?.dataViews || [];
    for (const dv of dvs) await gql(`mutation { deleteDataView(id: "${dv.id}") }`, token);

    const cvs = (await gql('{ customViews { id } }', token))?.data?.customViews || [];
    for (const cv of cvs) await gql(`mutation { deleteCustomView(id: "${cv.id}") }`, token);

    // Supprime tout espace utilisateur hors de l'application Bibliothèque
    const spaces = (await gql('{ spaces { id name } }', token))?.data?.spaces || [];
    let removed = 0;
    for (const sp of spaces) {
      if (!DEMO_SPACES.includes(sp.name)) {
        await gql(`mutation { deleteSpace(id: "${sp.id}") }`, token);
        removed++;
      }
    }
    console.log(`✅ Baseline rétablie (${dvs.length} data views, ${cvs.length} pages, ${removed} espaces de test supprimés)`);
  } catch (error) {
    // Ne bloque pas le run : on log seulement (la base peut déjà être propre).
    console.warn('⚠️ Nettoyage partiel/ignoré:', error.message);
  }

  return config;
};
