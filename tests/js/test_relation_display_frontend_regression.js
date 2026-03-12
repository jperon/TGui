(function() {
  // tests/js/test_relation_display_frontend_regression.coffee
  // Targeted regressions for frontend relation rendering.
  var appSource, assert, dataViewSource, describe, fs, helpersSource, it, path, root, summary;

  fs = require('fs');

  path = require('path');

  ({describe, it, assert, summary} = require('./runner'));

  root = path.resolve(__dirname, '../..');

  appSource = fs.readFileSync(path.join(root, 'frontend/src/app.coffee'), 'utf8');

  helpersSource = fs.readFileSync(path.join(root, 'frontend/src/app_fields_helpers.coffee'), 'utf8');

  dataViewSource = fs.readFileSync(path.join(root, 'frontend/src/views/data_view.coffee'), 'utf8');

  describe("Relation display frontend regression", function() {
    it("keeps arrow + tooltip format in fields list", function() {
      var hasBadge, hasTitle;
      hasBadge = appSource.includes('badge.textContent = "→ #{targetName}"') || helpersSource.includes('badge.textContent = "→ #{targetName}"');
      hasTitle = appSource.includes('badge.title = "Relation vers #{targetName}"') || helpersSource.includes('badge.title = "Relation vers #{targetName}"');
      assert(hasBadge, "arrow format regression");
      return assert(hasTitle, "relation tooltip regression");
    });
    return it("keeps relation rendering via _repr then fkMap", function() {
      assert(dataViewSource.includes('row["_repr_#{fieldName}"]?'), "check _repr absent");
      assert(dataViewSource.includes('displayVal = row["_repr_#{fieldName}"]'), "missing _repr assignment");
      return assert(dataViewSource.includes('fkMap[String val]'), "missing fkMap fallback");
    });
  });

  summary();

}).call(this);
