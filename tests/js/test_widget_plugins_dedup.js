(function() {
  // tests/js/test_widget_plugins_dedup.coffee
  // T13 guard: LIST_WIDGET_PLUGINS must be defined in exactly one frontend source
  // (widget_plugins.coffee), and app.coffee's _listWidgetPluginsQuery must keep
  // the exact same query text, character for character.
  var REFERENCE, SRC_DIR, assert, describe, eq, fs, it, path, summary;

  fs = require('fs');

  path = require('path');

  require('./dom_stub');

  ({describe, it, eq, assert, summary} = require('./runner'));

  SRC_DIR = path.join(__dirname, '../../frontend/src');

  // Canonical pre-refactor text: the identical heredoc that existed in BOTH
  // app.coffee (old lines 33-46) and widget_plugins.coffee (lines 4-17).
  REFERENCE = `query {
  widgetPlugins {
    id
    name
    description
    scriptLanguage
    templateLanguage
    scriptCode
    templateCode
    updatedAt
  }
}`;

  global.GQL = {
    query: (function() {
      return Promise.resolve({});
    }),
    mutate: (function() {
      return Promise.resolve({});
    }),
    loadToken: (function() {})
  };

  require('../../frontend/src/widget_plugins');

  require('../../frontend/src/app');

  describe('T13 widget plugin query dedup', function() {
    it('expose la requête via window.WidgetPlugins.LIST_QUERY', function() {
      return eq(typeof global.window.WidgetPlugins.LIST_QUERY, 'string');
    });
    it('conserve le texte de la requête caractère pour caractère (widget_plugins)', function() {
      return eq(global.window.WidgetPlugins.LIST_QUERY, REFERENCE);
    });
    it('conserve le texte de la requête caractère pour caractère (app)', function() {
      return eq(global.window.App._listWidgetPluginsQuery, REFERENCE);
    });
    it('app lit la même valeur que widget_plugins (pas de seconde définition)', function() {
      return eq(global.window.App._listWidgetPluginsQuery, global.window.WidgetPlugins.LIST_QUERY);
    });
    return it('ne définit LIST_WIDGET_PLUGINS que dans un seul fichier source', function() {
      var content, defs, f, files, i, len;
      files = fs.readdirSync(SRC_DIR).filter(function(f) {
        return f.match(/\.coffee$/);
      }).map(function(f) {
        return path.join(SRC_DIR, f);
      });
      defs = [];
      for (i = 0, len = files.length; i < len; i++) {
        f = files[i];
        content = fs.readFileSync(f, 'utf8');
        if (/^LIST_WIDGET_PLUGINS\s*=/m.test(content)) {
          defs.push(path.basename(f));
        }
      }
      eq(defs.length, 1, `définitions trouvées: ${defs.join(', ')}`);
      return eq(defs[0], 'widget_plugins.coffee');
    });
  });

  summary();

}).call(this);
