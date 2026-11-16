(function() {
  // tests/js/dom_stub.coffee — minimal DOM stub for Node.js
  // Expose global.window, global.document, global.localStorage, global.fetch
  // (no jsdom dependency)
  var _elementsById, _lsStore, fetchStub, localStorageStub, makeElement;

  makeElement = function(tag) {
    var classValue, classes, el;
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
      children: [], // alias synchronized by appendChild
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
        // Non énumérable pour ne pas casser JSON.stringify(el) dans les tests.
        Object.defineProperty(child, 'parentNode', {
          value: el,
          configurable: true,
          writable: true,
          enumerable: false
        });
        return child;
      },
      removeChild: function(child) {
        var i, j;
        i = el._children.indexOf(child);
        if (i !== -1) {
          el._children.splice(i, 1);
        }
        j = el.children.indexOf(child);
        if (j !== -1) {
          el.children.splice(j, 1);
        }
        child.parentNode = null;
        return child;
      },
      insertBefore: function(child, _ref) {
        el._children.unshift(child);
        el.children.unshift(child);
        return child;
      },
      getAttribute: function(name) {
        var ref, ref1;
        if (name.indexOf('data-') === 0) {
          return el.dataset[name.slice(5)];
        }
        return (ref = (ref1 = el._attrs) != null ? ref1[name] : void 0) != null ? ref : null;
      },
      setAttribute: function(name, value) {
        if (name.indexOf('data-') === 0) {
          return el.dataset[name.slice(5)] = value;
        } else {
          return (el._attrs != null ? el._attrs : el._attrs = {})[name] = value;
        }
      },
      addEventListener: function(ev, fn) {
        var base;
        if ((base = el._listeners)[ev] == null) {
          base[ev] = [];
        }
        return el._listeners[ev].push(fn);
      },
      removeEventListener: function(ev, fn) {
        var i, list;
        list = el._listeners[ev];
        if (!list) {
          return;
        }
        i = list.indexOf(fn);
        if (i !== -1) {
          return list.splice(i, 1);
        }
      },
      // Retourne un élément stub (mémoïsé par sélecteur) plutôt que null, afin que
      // le code qui enchaîne .querySelector(x).addEventListener(...) ne plante pas.
      querySelector: function(sel) {
        var base;
        if (el._qsCache == null) {
          el._qsCache = {};
        }
        return (base = el._qsCache)[sel] != null ? base[sel] : base[sel] = makeElement('div');
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
      },
      contains: function(node) {
        if (node == null) {
          return false;
        }
        if (node === el) {
          return true;
        }
        return el._children.indexOf(node) !== -1;
      }
    };
    // `className` affecté directement doit alimenter classList (comme dans le DOM),
    // sinon `el.className = 'a b'` puis `classList.contains('a')` est faux.
    classValue = '';
    Object.defineProperty(el, 'className', {
      get: function() {
        return classValue;
      },
      set: function(value) {
        var c, l, len, ref;
        classValue = value != null ? String(value) : '';
        classes.clear();
        ref = classValue.split(/\s+/);
        for (l = 0, len = ref.length; l < len; l++) {
          c = ref[l];
          if (c) {
            classes.add(c);
          }
        }
      }
    });
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
      return _lsStore; // helper for tests
    }
  };

  
  // --- fetch stub (configurable par test) -------------------------------------
  // By default returns {} (no errors). Replace global.fetch in tests as needed.
  fetchStub = function(url, opts) {
    return Promise.resolve({
      json: function() {
        return Promise.resolve({});
      }
    });
  };

  global.window = {
    addEventListener: (function() {}),
    removeEventListener: (function() {})
  };

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
    activeElement: null,
    _setById: function(id, el) {
      return _elementsById[id] = el; // helper for tests
    }
  };

  module.exports = {makeElement, localStorageStub};

}).call(this);
