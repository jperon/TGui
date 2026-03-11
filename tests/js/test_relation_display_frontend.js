(function() {
  // tests/js/test_relation_display_frontend.coffee
  // Tests statiques frontend (Node) pour l'affichage des relations.
  var appSource, assert, dataViewSource, describe, fs, it, path, root, summary;

  fs = require('fs');

  path = require('path');

  ({describe, it, assert, summary} = require('./runner'));

  root = path.resolve(__dirname, '../..');

  appSource = fs.readFileSync(path.join(root, 'frontend/src/app.coffee'), 'utf8');

  dataViewSource = fs.readFileSync(path.join(root, 'frontend/src/views/data_view.coffee'), 'utf8');

  describe("Relation display frontend", function() {
    it("affiche un badge de relation avec une flèche", function() {
      assert(/badge\.textContent\s*=\s*"→ #\{targetName\}"/.test(appSource), "format relation badge manquant");
      return assert(/badge\.title\s*=\s*"Relation vers #\{targetName\}"/.test(appSource), "tooltip relation manquant");
    });
    return it("utilise _repr pour afficher les FK dans la grille", function() {
      assert(/row\["_repr_#\{fieldName\}"\]\?/.test(dataViewSource), "_repr relation manquant");
      assert(/displayVal\s*=\s*row\["_repr_#\{fieldName\}"\]/.test(dataViewSource), "fallback displayVal _repr manquant");
      return assert(/fkMap\[String val\]/.test(dataViewSource), "lookup fkMap manquant");
    });
  });

  summary();

}).call(this);
