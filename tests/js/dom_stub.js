(function() {
  // tests/js/dom_stub.coffee — stub DOM minimal pour Node.js
  // Expose global.window, global.document, global.localStorage, global.fetch
  // (pas de dépendance jsdom)
  var _elementsById, _lsStore, fetchStub, localStorageStub, makeElement;

  makeElement = function(tag) {
    var classes, el;
    classes = new Set();
    el = {
      tagName: tag.toUpperCase(),
      style: {},
      className: '',
      textContent: '',
      innerHTML: '',
      title: '',
      dataset: {},
      _children: [],
      _listeners: {},
      children: [], // alias synchronisé par appendChild
      classList: {
        add: function(c) {
          classes.add(c);
          return el.className = [...classes].join(' ');
        },
        remove: function(c) {
          classes.delete(c);
          return el.className = [...classes].join(' ');
        },
        contains: function(c) {
          return classes.has(c);
        },
        toggle: function(c, force) {
          var next;
          next = force !== void 0 ? force : !classes.has(c);
          if (next) {
            return el.classList.add(c);
          } else {
            return el.classList.remove(c);
          }
        }
      },
      appendChild: function(child) {
        el._children.push(child);
        el.children.push(child);
        return child;
      },
      addEventListener: function(ev, fn) {
        var base;
        if ((base = el._listeners)[ev] == null) {
          base[ev] = [];
        }
        return el._listeners[ev].push(fn);
      },
      querySelector: function() {
        return null;
      },
      querySelectorAll: function() {
        return [];
      },
      getBoundingClientRect: function() {
        return {
          top: 0,
          left: 0,
          width: 100,
          height: 100
        };
      }
    };
    return el;
  };

  _elementsById = {};

  // --- localStorage stub -------------------------------------------------------
  _lsStore = {};

  localStorageStub = {
    getItem: function(k) {
      var ref;
      return (ref = _lsStore[k]) != null ? ref : null;
    },
    setItem: function(k, v) {
      return _lsStore[k] = String(v);
    },
    removeItem: function(k) {
      return delete _lsStore[k];
    },
    clear: function() {
      return _lsStore = {};
    },
    _store: function() {
      return _lsStore; // helper pour les tests
    }
  };

  
  // --- fetch stub (configurable par test) -------------------------------------
  // Par défaut, retourne {} (pas d'erreurs). Remplacer global.fetch dans les tests.
  fetchStub = function(url, opts) {
    return Promise.resolve({
      json: function() {
        return Promise.resolve({});
      }
    });
  };

  global.window = {};

  global.localStorage = localStorageStub;

  global.fetch = fetchStub;

  global.history = {
    replaceState: function() {}
  };

  global.navigator = {
    clipboard: {
      readText: function() {
        return Promise.resolve('');
      }
    }
  };

  global.document = {
    createElement: function(tag) {
      return makeElement(tag);
    },
    getElementById: function(id) {
      return _elementsById[id] || null;
    },
    querySelector: function() {
      return null;
    },
    querySelectorAll: function() {
      return [];
    },
    addEventListener: function() {},
    removeEventListener: function() {},
    _setById: function(id, el) {
      return _elementsById[id] = el; // helper pour les tests
    }
  };

  module.exports = {makeElement, localStorageStub};

}).call(this);
