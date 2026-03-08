(function() {
  // tests/js/dom_stub.coffee — stub DOM minimal pour Node.js
  // Expose global.window, global.document (pas de dépendance jsdom)
  var _elementsById, makeElement;

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

  global.window = {};

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
    _setById: function(id, el) {
      return _elementsById[id] = el; // helper pour les tests
    }
  };

  module.exports = {makeElement};

}).call(this);
