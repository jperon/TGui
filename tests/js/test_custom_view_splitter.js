(function() {
  // tests/js/test_custom_view_splitter.coffee
  // Séparateur (splitter) entre deux enfants d'une zone :
  //  - les écouteurs document sont posés au mousedown et retirés au mouseup ;
  //  - un simple clic ne réécrit pas le YAML (donc pas de perte de commentaires) ;
  //  - pendant le glisser, les deux voisins sont répartis en FACTEURS dont la
  //    somme est conservée : les autres enfants de la zone ne bougent pas.
  var CV, DataView, approx, assert, deepEq, describe, docListeners, eq, findByClass, it, listenCount, makeLayout, makePage, makeSpaces, mouseDown, mouseMove, mouseUp, resetDocListeners, setup, summary,
    hasProp = {}.hasOwnProperty;

  require('./dom_stub');

  ({describe, it, eq, deepEq, assert, summary} = require('./runner'));

  global.jsyaml = {
    load: function(src) {
      return JSON.parse(src);
    }
  };

  global.DataView = DataView = class DataView {
    constructor(container1, space) {
      this.container = container1;
      this.space = space;
    }

    mount() {
      return Promise.resolve();
    }

    refreshLayout() {}

    unmount() {}

    deleteSelected() {}

  };

  require('../../frontend/src/views/custom_view');

  require('../../frontend/src/views/custom_view_plugins');

  require('../../frontend/src/views/custom_view_aggregate');

  require('../../frontend/src/views/custom_view_resize');

  CV = global.window.CustomView;

  // --- document instrumenté ----------------------------------------------------
  global.document.body = global.document.createElement('body');

  docListeners = {};

  global.document.addEventListener = function(ev, fn) {
    return (docListeners[ev] != null ? docListeners[ev] : docListeners[ev] = []).push(fn);
  };

  global.document.removeEventListener = function(ev, fn) {
    var i, list, ref;
    list = (ref = docListeners[ev]) != null ? ref : [];
    i = list.indexOf(fn);
    if (i !== -1) {
      return list.splice(i, 1);
    }
  };

  resetDocListeners = function() {
    var ev;
    for (ev in docListeners) {
      if (!hasProp.call(docListeners, ev)) continue;
      delete docListeners[ev];
    }
    return docListeners = {};
  };

  listenCount = function(ev) {
    var ref;
    return ((ref = docListeners[ev]) != null ? ref : []).length;
  };

  // --- helpers -----------------------------------------------------------------
  makeSpaces = function() {
    return [
      {
        id: '1',
        name: 'personnes',
        fields: [
          {
            id: 'f1',
            name: 'nom',
            fieldType: 'Str'
          }
        ]
      }
    ];
  };

  makePage = function(layout) {
    var container, cv;
    container = global.document.createElement('div');
    container.setAttribute('data-page-id', 'page1');
    cv = new CV(container, JSON.stringify(layout), makeSpaces());
    cv.mount();
    return cv;
  };

  findByClass = function(el, cls) {
    var child, found, j, len, ref;
    if (typeof el.className === 'string' && el.className.split(' ').indexOf(cls) !== -1) {
      return el;
    }
    ref = el._children || el.children || [];
    for (j = 0, len = ref.length; j < len; j++) {
      child = ref[j];
      found = findByClass(child, cls);
      if (found) {
        return found;
      }
    }
    return null;
  };

  // Zone horizontale à trois enfants : la paire (2,1) est séparée de (4).
  makeLayout = function() {
    return {
      layout: {
        direction: 'horizontal',
        children: [
          {
            factor: 2,
            widget: {
              id: 'w1',
              space: 'personnes'
            }
          },
          {
            factor: 1,
            widget: {
              id: 'w2',
              space: 'personnes'
            }
          },
          {
            factor: 4,
            widget: {
              id: 'w3',
              space: 'personnes'
            }
          }
        ]
      }
    };
  };

  setup = function() {
    var cv, saved, splitter, widgets;
    resetDocListeners();
    cv = makePage(makeLayout());
    splitter = findByClass(cv.container, 'cv-splitter');
    assert(splitter != null, 'un séparateur est attendu entre w1 et w2');
    widgets = cv._widgets;
    saved = [];
    cv._saveChildFactors = function(path, factors) {
      saved.push({path, factors});
      return Promise.resolve();
    };
    return {
      cv,
      splitter,
      saved,
      w1: widgets[0].el,
      w2: widgets[1].el,
      w3: widgets[2].el
    };
  };

  mouseDown = function(splitter, x = 0) {
    return splitter._listeners.mousedown[0]({
      clientX: x,
      preventDefault: function() {}
    });
  };

  mouseMove = function(x) {
    return docListeners.mousemove[0]({
      clientX: x
    });
  };

  mouseUp = function() {
    return docListeners.mouseup[0]({});
  };

  approx = function(a, b, tol = 0.01) {
    return Math.abs(a - b) <= tol;
  };

  describe('CustomView — séparateur de zones', function() {
    it('ne pose les écouteurs document qu’au mousedown', function() {
      var splitter;
      ({splitter} = setup());
      eq(listenCount('mousemove'), 0);
      eq(listenCount('mouseup'), 0);
      mouseDown(splitter);
      eq(listenCount('mousemove'), 1);
      eq(listenCount('mouseup'), 1);
      mouseUp();
      eq(listenCount('mousemove'), 0);
      return eq(listenCount('mouseup'), 0);
    });
    it('un simple clic ne modifie pas le YAML', function() {
      var before, saved, splitter, w1, w2;
      ({splitter, saved, w1, w2} = setup());
      before = [w1.style.flex, w2.style.flex];
      mouseDown(splitter);
      mouseUp();
      eq(saved.length, 0);
      return deepEq([w1.style.flex, w2.style.flex], before);
    });
    it('conserve la somme des facteurs de la paire pendant le glisser', function() {
      var f, fa, fb, saved, splitter, w1, w2, w3;
      ({splitter, saved, w1, w2, w3} = setup());
      deepEq([w1.style.flex, w2.style.flex, w3.style.flex], ['2', '1', '4']);
      mouseDown(splitter, 0);
      // 100 px par voisin, +30 px : le minimum de 80 px borne la paire à 120/80.
      mouseMove(30);
      mouseUp();
      eq(saved.length, 1);
      [fa, fb] = (function() {
        var j, len, ref, results;
        ref = saved[0].factors;
        results = [];
        for (j = 0, len = ref.length; j < len; j++) {
          f = ref[j];
          results.push(f.factor);
        }
        return results;
      })();
      assert(approx(fa + fb, 3), `la paire doit garder sa somme (3), got ${fa + fb}`);
      assert(approx(fa, 1.8), `facteur du premier voisin, got ${fa}`);
      assert(approx(fb, 1.2), `facteur du second voisin, got ${fb}`);
      // Le troisième enfant de la zone ne bouge pas : sa somme de facteurs (3)
      // face au reste de la zone reste comparable (4 face à 3, pas 200 px).
      eq(w3.style.flex, '4');
      return assert(approx(parseFloat(w1.style.flex) + parseFloat(w2.style.flex), 3), `flex affichés : ${w1.style.flex} + ${w2.style.flex}`);
    });
    it('enregistre les facteurs de la bonne paire, au bon endroit du YAML', function() {
      var f, saved, splitter;
      ({splitter, saved} = setup());
      mouseDown(splitter, 0);
      mouseMove(-20);
      mouseUp();
      eq(saved.length, 1);
      deepEq((function() {
        var j, len, ref, results;
        ref = saved[0].factors;
        results = [];
        for (j = 0, len = ref.length; j < len; j++) {
          f = ref[j];
          results.push(f.index);
        }
        return results;
      })(), [0, 1]);
      return eq(saved[0].path.length, 0);
    });
    return it('ne enregistre plus après le mouseup (écouteurs retirés)', function() {
      var saved, splitter;
      ({splitter, saved} = setup());
      mouseDown(splitter, 0);
      mouseMove(10);
      mouseUp();
      eq(saved.length, 1);
      // Un mousemove fantôme après le relâchement ne doit rien déclencher.
      eq(listenCount('mousemove'), 0);
      return eq(saved.length, 1);
    });
  });

  summary();

}).call(this);
