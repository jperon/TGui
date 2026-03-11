(function() {
  // tests/js/test_relation_display_frontend_regression.coffee
  // Régressions ciblées sur le rendu des relations côté frontend.
  var appSource, assert, dataViewSource, describe, fs, it, path, root, summary;

  fs = require('fs');

  path = require('path');

  ({describe, it, assert, summary} = require('./runner'));

  root = path.resolve(__dirname, '../..');

  appSource = fs.readFileSync(path.join(root, 'frontend/src/app.coffee'), 'utf8');

  dataViewSource = fs.readFileSync(path.join(root, 'frontend/src/views/data_view.coffee'), 'utf8');

  describe("Relation display frontend regression", function() {
    it("conserve le format flèche + tooltip dans la liste des champs", function() {
      assert(appSource.includes('badge.textContent = "→ #{targetName}"'), "format flèche régression");
      return assert(appSource.includes('badge.title = "Relation vers #{targetName}"'), "tooltip relation régression");
    });
    return it("conserve le rendu relation via _repr puis fkMap", function() {
      assert(dataViewSource.includes('row["_repr_#{fieldName}"]?'), "check _repr absent");
      assert(dataViewSource.includes('displayVal = row["_repr_#{fieldName}"]'), "assign _repr absente");
      return assert(dataViewSource.includes('fkMap[String val]'), "fallback fkMap absent");
    });
  });

  summary();

}).call(this);
