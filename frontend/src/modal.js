(function() {
  // modal.coffee — Promise-based async replacements for alert(), confirm(), prompt().
  // Usage:
  //   await tdbAlert "Error message", 'error'
  //   if await tdbConfirm "Delete?"
  //   name = await tdbPrompt "Name:", "default value"
  var _box, _cancelBtn, _close, _hide, _init, _input, _msg, _okBtn, _overlay, _show, _t;

  _overlay = null;

  _box = null;

  _msg = null;

  _input = null;

  _okBtn = null;

  _cancelBtn = null;

  _t = function(key, vars = {}) {
    var ref;
    if ((ref = window.I18N) != null ? ref.t : void 0) {
      return window.I18N.t(key, vars);
    } else {
      return key;
    }
  };

  _init = function() {
    var btns;
    if (_overlay) {
      return;
    }
    _overlay = document.createElement('div');
    _overlay.id = 'tdb-modal-overlay';
    _overlay.className = 'tdb-modal-overlay hidden';
    _box = document.createElement('div');
    _box.className = 'tdb-modal-box';
    _msg = document.createElement('p');
    _msg.className = 'tdb-modal-msg';
    _input = document.createElement('input');
    _input.type = 'text';
    _input.className = 'tdb-modal-input hidden';
    btns = document.createElement('div');
    btns.className = 'tdb-modal-actions';
    _cancelBtn = document.createElement('button');
    _cancelBtn.className = 'toolbar-btn';
    _cancelBtn.textContent = _t('common.cancel');
    _okBtn = document.createElement('button');
    _okBtn.className = 'btn-primary';
    _okBtn.textContent = _t('common.ok');
    btns.appendChild(_cancelBtn);
    btns.appendChild(_okBtn);
    _box.appendChild(_msg);
    _box.appendChild(_input);
    _box.appendChild(btns);
    _overlay.appendChild(_box);
    return document.body.appendChild(_overlay);
  };

  _show = function(msg, type = 'info', showInput = false, defaultVal = '', showCancel = false) {
    _init();
    _okBtn.textContent = _t('common.ok');
    _cancelBtn.textContent = _t('common.cancel');
    _msg.textContent = msg;
    _box.className = `tdb-modal-box tdb-modal-box--${type}`;
    if (showInput) {
      _input.classList.remove('hidden');
      _input.value = defaultVal;
    } else {
      _input.classList.add('hidden');
    }
    if (showCancel) {
      _cancelBtn.classList.remove('hidden');
    } else {
      _cancelBtn.classList.add('hidden');
    }
    _overlay.classList.remove('hidden');
    if (showInput) {
      return _input.focus();
    } else {
      return _okBtn.focus();
    }
  };

  _hide = function() {
    _overlay.classList.add('hidden');
    return _input.value = '';
  };

  // Retire le handler keydown puis cache la modale. Utilisé par TOUS les chemins
  // de fermeture (clic OK, clic Annuler, Échap, Entrée) : sans cela, fermer par
  // clic laissait le handler attaché (fuite d'écouteurs + handler périmé).
  _close = function(handler) {
    document.removeEventListener('keydown', handler);
    return _hide();
  };

  // alert-like: shows a message and resolves when the user clicks OK.
  window.tdbAlert = function(msg, type = 'info') {
    return new Promise(function(resolve) {
      var handler;
      _show(msg, type, false, '', false);
      _okBtn.onclick = function() {
        _close(handler);
        return resolve();
      };
      // Also close on Escape.
      handler = function(e) {
        if (e.key === 'Escape' || e.key === 'Enter') {
          _close(handler);
          return resolve();
        }
      };
      return document.addEventListener('keydown', handler);
    });
  };

  // confirm-like: resolves true/false.
  window.tdbConfirm = function(msg, type = 'warn') {
    return new Promise(function(resolve) {
      var handler;
      _show(msg, type, false, '', true);
      _okBtn.onclick = function() {
        _close(handler);
        return resolve(true);
      };
      _cancelBtn.onclick = function() {
        _close(handler);
        return resolve(false);
      };
      handler = function(e) {
        if (e.key === 'Escape') {
          _close(handler);
          return resolve(false);
        } else if (e.key === 'Enter') {
          _close(handler);
          return resolve(true);
        }
      };
      return document.addEventListener('keydown', handler);
    });
  };

  // prompt-like: resolves with input string or null if canceled.
  window.tdbPrompt = function(msg, defaultVal = '', type = 'info') {
    return new Promise(function(resolve) {
      var handler;
      _show(msg, type, true, defaultVal, true);
      _okBtn.onclick = function() {
        var val;
        val = _input.value;
        _close(handler);
        return resolve(val.trim() ? val : null);
      };
      _cancelBtn.onclick = function() {
        _close(handler);
        return resolve(null);
      };
      handler = function(e) {
        var val;
        if (e.key === 'Escape') {
          _close(handler);
          return resolve(null);
        } else if (e.key === 'Enter') {
          val = _input.value;
          _close(handler);
          return resolve(val.trim() ? val : null);
        }
      };
      return document.addEventListener('keydown', handler);
    });
  };

}).call(this);
