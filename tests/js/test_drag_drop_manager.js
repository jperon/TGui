(function() {
  // tests/js/test_drag_drop_manager.coffee - tests for DragDropManager
  var Sortable, assert, describe, eq, it, summary;

  require('./dom_stub');

  ({describe, it, eq, assert, summary} = require('./runner'));

  global.window = global.window || {};

  global.document = global.document || {};

  global.Sortable = global.Sortable || (Sortable = class Sortable {
    constructor(el, opts) {
      this.el = el;
      this.opts = opts;
    }

    option(key, value) {
      if (value !== void 0) {
        this.opts[key] = value;
      }
      return this.opts[key];
    }

    destroy() {}

  });

  global.document.createElement = function(tag) {
    return {
      tagName: tag.toUpperCase(),
      classList: {
        add: function() {},
        remove: function() {},
        contains: function() {
          return false;
        }
      },
      querySelectorAll: function() {
        return [];
      },
      addEventListener: function() {},
      setAttribute: function() {},
      getAttribute: function() {
        return null;
      },
      parentElement: null,
      closest: function() {
        return null;
      }
    };
  };

  global.document.body = global.document.body || {
    classList: {
      add: function() {},
      remove: function() {}
    }
  };

  require('../../frontend/src/drag_drop_manager');

  describe('DragDropManager', function() {
    it('exports DragDropManager class', function() {
      return eq(typeof window.DragDropManager, 'function');
    });
    it('can be instantiated with container and options', function() {
      var container, ddm;
      container = document.createElement('div');
      ddm = new window.DragDropManager(container, {
        pageId: 'test-page'
      });
      return assert(ddm !== null, 'DragDropManager instance should exist');
    });
    it('stores container reference', function() {
      var container, ddm;
      container = document.createElement('div');
      ddm = new window.DragDropManager(container, {
        pageId: 'test-page'
      });
      return eq(ddm.container, container);
    });
    it('stores options', function() {
      var container, ddm, opts;
      container = document.createElement('div');
      opts = {
        pageId: 'test-page',
        foo: 'bar'
      };
      ddm = new window.DragDropManager(container, opts);
      return eq(ddm.options.foo, 'bar');
    });
    it('initializes with null sortable when no container', function() {
      var ddm;
      ddm = new window.DragDropManager(null, {
        pageId: 'test-page'
      });
      return eq(ddm.sortable, null);
    });
    it('has extractWidgetPositions method', function() {
      var container, ddm;
      container = document.createElement('div');
      ddm = new window.DragDropManager(container, {
        pageId: 'test-page'
      });
      return eq(typeof ddm.extractWidgetPositions, 'function');
    });
    it('has enable and disable methods', function() {
      var container, ddm;
      container = document.createElement('div');
      ddm = new window.DragDropManager(container, {
        pageId: 'test-page'
      });
      assert(typeof ddm.enable === 'function', 'enable should be a function');
      return assert(typeof ddm.disable === 'function', 'disable should be a function');
    });
    it('has destroy method', function() {
      var container, ddm;
      container = document.createElement('div');
      ddm = new window.DragDropManager(container, {
        pageId: 'test-page'
      });
      return eq(typeof ddm.destroy, 'function');
    });
    it('has getWidgetOrder method', function() {
      var container, ddm;
      container = document.createElement('div');
      ddm = new window.DragDropManager(container, {
        pageId: 'test-page'
      });
      return eq(typeof ddm.getWidgetOrder, 'function');
    });
    it('has zone management methods', function() {
      var container, ddm;
      container = document.createElement('div');
      ddm = new window.DragDropManager(container, {
        pageId: 'test-page'
      });
      assert(typeof ddm.scanZones === 'function', 'scanZones should be a function');
      assert(typeof ddm.getZoneById === 'function', 'getZoneById should be a function');
      return assert(typeof ddm.createZone === 'function', 'createZone should be a function');
    });
    return it('has updatePageId method', function() {
      var container, ddm;
      container = document.createElement('div');
      ddm = new window.DragDropManager(container, {
        pageId: 'test-page'
      });
      ddm.updatePageId('new-page-id');
      return eq(ddm.currentPageId, 'new-page-id');
    });
  });

  summary();

}).call(this);
