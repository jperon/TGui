(function() {
  // modal.coffee — Remplaçants promisifiés pour alert(), confirm(), prompt()
  // Usage :
  //   await tdbAlert "Message d'erreur", 'error'
  //   if await tdbConfirm "Supprimer ?"
  //   name = await tdbPrompt "Nom :", "valeur par défaut"
  var _box, _cancelBtn, _hide, _init, _input, _msg, _okBtn, _overlay, _show;

  _overlay = null;

  _box = null;

  _msg = null;

  _input = null;

  _okBtn = null;

  _cancelBtn = null;

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
    _cancelBtn.textContent = 'Annuler';
    _okBtn = document.createElement('button');
    _okBtn.className = 'btn-primary';
    _okBtn.textContent = 'OK';
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

  // alert-like : affiche un message, résout quand l'utilisateur clique OK
  window.tdbAlert = function(msg, type = 'info') {
    return new Promise(function(resolve) {
      var handler;
      _show(msg, type, false, '', false);
      _okBtn.onclick = function() {
        _hide();
        return resolve();
      };
      // Fermer aussi avec Escape
      handler = function(e) {
        if (e.key === 'Escape' || e.key === 'Enter') {
          document.removeEventListener('keydown', handler);
          _hide();
          return resolve();
        }
      };
      return document.addEventListener('keydown', handler);
    });
  };

  // confirm-like : résout true/false
  window.tdbConfirm = function(msg, type = 'warn') {
    return new Promise(function(resolve) {
      var handler;
      _show(msg, type, false, '', true);
      _okBtn.onclick = function() {
        _hide();
        return resolve(true);
      };
      _cancelBtn.onclick = function() {
        _hide();
        return resolve(false);
      };
      handler = function(e) {
        if (e.key === 'Escape') {
          document.removeEventListener('keydown', handler);
          _hide();
          return resolve(false);
        } else if (e.key === 'Enter') {
          document.removeEventListener('keydown', handler);
          _hide();
          return resolve(true);
        }
      };
      return document.addEventListener('keydown', handler);
    });
  };

  // prompt-like : résout avec la chaîne saisie ou null si annulé
  window.tdbPrompt = function(msg, defaultVal = '', type = 'info') {
    return new Promise(function(resolve) {
      var handler;
      _show(msg, type, true, defaultVal, true);
      _okBtn.onclick = function() {
        var val;
        val = _input.value;
        _hide();
        return resolve(val.trim() ? val : null);
      };
      _cancelBtn.onclick = function() {
        _hide();
        return resolve(null);
      };
      handler = function(e) {
        var val;
        if (e.key === 'Escape') {
          document.removeEventListener('keydown', handler);
          _hide();
          return resolve(null);
        } else if (e.key === 'Enter') {
          document.removeEventListener('keydown', handler);
          val = _input.value;
          _hide();
          return resolve(val.trim() ? val : null);
        }
      };
      return document.addEventListener('keydown', handler);
    });
  };

}).call(this);
