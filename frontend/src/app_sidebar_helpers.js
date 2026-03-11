(function() {
  // app_sidebar_helpers.coffee — sidebar/admin/dialog helpers extracted from app.coffee
  window.AppSidebarHelpers = {
    applySidebarState: function(app) {
      var spBtn, spList;
      if (localStorage.getItem('tdb_menu_state') === 'collapsed') {
        app.el.main().classList.add('sidebar-collapsed');
      } else {
        app.el.main().classList.remove('sidebar-collapsed');
      }
      spList = app.el.spaceList();
      spBtn = document.getElementById('spaces-toggle-btn');
      if (localStorage.getItem('tdb_spaces_collapsed') === 'true') {
        spList.classList.add('hidden');
        return spBtn != null ? spBtn.classList.add('collapsed') : void 0;
      } else {
        spList.classList.remove('hidden');
        return spBtn != null ? spBtn.classList.remove('collapsed') : void 0;
      }
    },
    bindSidebar: function(app) {
      var ref, ref1, ref2, ref3;
      app.el.newSpaceBtn().addEventListener('click', async function() {
        var name;
        name = (await tdbPrompt(app._t('ui.prompts.newSpace')));
        if (!(name != null ? name.trim() : void 0)) {
          return;
        }
        return Spaces.create(name.trim()).then(function() {
          return app._loadAll();
        }).catch(function(err) {
          return tdbAlert(app._err(err), 'error');
        });
      });
      app.el.newViewBtn().addEventListener('click', async function() {
        var name;
        name = (await tdbPrompt(app._t('ui.prompts.newView')));
        if (!(name != null ? name.trim() : void 0)) {
          return;
        }
        return GQL.mutate(app._createCustomViewMutation, {
          input: {
            name: name.trim(),
            yaml: "layout:\n  direction: vertical\n  children: []\n"
          }
        }).then(function(data) {
          return app.loadCustomViews().then(function() {
            var cv;
            cv = data.createCustomView;
            return app.selectCustomView(cv);
          });
        }).catch(function(err) {
          return tdbAlert(app._err(err), 'error');
        });
      });
      if ((ref = document.getElementById('sidebar-toggle')) != null) {
        ref.addEventListener('click', function() {
          var isCollapsed, mainEl;
          mainEl = app.el.main();
          isCollapsed = mainEl.classList.contains('sidebar-collapsed');
          if (isCollapsed) {
            mainEl.classList.remove('sidebar-collapsed');
            return localStorage.removeItem('tdb_menu_state');
          } else {
            mainEl.classList.add('sidebar-collapsed');
            return localStorage.setItem('tdb_menu_state', 'collapsed');
          }
        });
      }
      if ((ref1 = document.getElementById('spaces-toggle-btn')) != null) {
        ref1.addEventListener('click', function() {
          var isHidden, spBtn, spList;
          spList = app.el.spaceList();
          spBtn = document.getElementById('spaces-toggle-btn');
          isHidden = spList.classList.contains('hidden');
          if (isHidden) {
            spList.classList.remove('hidden');
            spBtn.classList.remove('collapsed');
            return localStorage.setItem('tdb_spaces_collapsed', 'false');
          } else {
            spList.classList.add('hidden');
            spBtn.classList.add('collapsed');
            return localStorage.setItem('tdb_spaces_collapsed', 'true');
          }
        });
      }
      app._applySidebarState();
      app.el.currentUserBtn().addEventListener('click', function() {
        var menu;
        menu = app.el.userMenu();
        return menu.classList.toggle('hidden');
      });
      document.addEventListener('click', function(e) {
        if (!(app.el.currentUserBtn().contains(e.target) || app.el.userMenu().contains(e.target))) {
          return app.el.userMenu().classList.add('hidden');
        }
      });
      app.el.changePasswordBtn().addEventListener('click', function() {
        app.el.userMenu().classList.add('hidden');
        return app._openChangePasswordDialog();
      });
      app.el.logoutBtn().addEventListener('click', function() {
        return Auth.logout();
      });
      if ((ref2 = app.el.langFrBtn()) != null) {
        ref2.addEventListener('click', function() {
          var ref3;
          return (ref3 = window.I18N) != null ? ref3.setLocale('fr') : void 0;
        });
      }
      if ((ref3 = app.el.langEnBtn()) != null) {
        ref3.addEventListener('click', function() {
          var ref4;
          return (ref4 = window.I18N) != null ? ref4.setLocale('en') : void 0;
        });
      }
      app.el.adminNavUsers().addEventListener('click', function() {
        return app._showAdminPanel('users');
      });
      app.el.adminNavGroups().addEventListener('click', function() {
        return app._showAdminPanel('groups');
      });
      app.el.adminNavSnapshot().addEventListener('click', function() {
        return app._showAdminPanel('snapshot');
      });
      app.el.warningChangePasswordBtn().addEventListener('click', function() {
        return app._openChangePasswordDialog();
      });
      app._bindChangePasswordDialog();
      app._bindCreateUserDialog();
      app._bindCreateGroupDialog();
      return app._bindSnapshotPanel();
    },
    showAdminPanel: function(app, section = 'users') {
      app.el.dataToolbar().classList.add('hidden');
      app.el.contentRow().classList.add('hidden');
      app.el.welcome().classList.add('hidden');
      app.el.yamlEditorPanel().classList.add('hidden');
      app.el.adminPanel().classList.remove('hidden');
      app.el.adminUsersSection().classList.add('hidden');
      app.el.adminGroupsSection().classList.add('hidden');
      app.el.adminSnapshotSection().classList.add('hidden');
      if (section === 'users') {
        app.el.adminUsersSection().classList.remove('hidden');
        return app._loadAdminUsers();
      } else if (section === 'groups') {
        app.el.adminGroupsSection().classList.remove('hidden');
        return app._loadAdminGroups();
      } else {
        return app.el.adminSnapshotSection().classList.remove('hidden');
      }
    },
    hideAdminPanel: function(app) {
      return app.el.adminPanel().classList.add('hidden');
    },
    loadAdminUsers: function(app) {
      return Auth.listUsers().then(function(users) {
        var btnPwd, groupNames, i, len, li, u, ul;
        ul = app.el.adminUsersList();
        ul.innerHTML = '';
        for (i = 0, len = users.length; i < len; i++) {
          u = users[i];
          li = document.createElement('li');
          li.className = 'admin-list-item';
          groupNames = (u.groups || []).map(function(g) {
            return g.name;
          }).join(', ') || '—';
          li.innerHTML = `<span class='admin-item-name'>${u.username}</span><span class='admin-item-meta'>${groupNames}</span>`;
          btnPwd = document.createElement('button');
          btnPwd.className = 'toolbar-btn';
          btnPwd.textContent = '🔑';
          btnPwd.title = app._t('ui.admin.pwdBtnTitle');
          btnPwd.addEventListener('click', async function() {
            var newPwd, uid;
            uid = u.id;
            newPwd = (await tdbPrompt(app._t('ui.prompts.newPasswordFor', {
              username: u.username
            })));
            if (!(newPwd != null ? newPwd.trim() : void 0)) {
              return;
            }
            return GQL.mutate('mutation SetPwd($uid: ID!, $pwd: String!) { adminSetPassword(userId: $uid, newPassword: $pwd) }', {
              uid,
              pwd: newPwd
            }).then(function() {
              return tdbAlert(app._t('ui.alerts.passwordChanged'), 'info');
            }).catch(function(err) {
              return tdbAlert(app._err(err), 'error');
            });
          });
          li.appendChild(btnPwd);
          ul.appendChild(li);
        }
        return app.el.adminCreateUserBtn().onclick = function() {
          return app.el.createUserDialog().classList.remove('hidden');
        };
      }).catch(function(err) {
        return tdbAlert(app._err(err), 'error');
      });
    },
    loadAdminGroups: function(app) {
      return Auth.listGroups().then(function(groups) {
        var btnDel, g, i, len, li, memberNames, ul;
        ul = app.el.adminGroupsList();
        ul.innerHTML = '';
        for (i = 0, len = groups.length; i < len; i++) {
          g = groups[i];
          li = document.createElement('li');
          li.className = 'admin-list-item';
          memberNames = (g.members || []).map(function(m) {
            return m.username;
          }).join(', ') || '—';
          li.innerHTML = `<span class='admin-item-name'>${g.name}</span><span class='admin-item-meta'>${memberNames}</span>`;
          if (g.name !== 'admin') {
            btnDel = document.createElement('button');
            btnDel.className = 'toolbar-btn toolbar-btn--icon toolbar-btn--danger';
            btnDel.textContent = '🗑';
            btnDel.title = app._t('ui.admin.deleteGroupTitle');
            btnDel.addEventListener('click', async function() {
              var gid, gname;
              gid = g.id;
              gname = g.name;
              if (!(await tdbConfirm(app._t('ui.confirms.deleteGroup', {
                name: gname
              })))) {
                return;
              }
              return Auth.deleteGroup(gid).then(function() {
                return app._loadAdminGroups();
              }).catch(function(err) {
                return tdbAlert(app._err(err), 'error');
              });
            });
            li.appendChild(btnDel);
          }
          ul.appendChild(li);
        }
        return app.el.adminCreateGroupBtn().onclick = function() {
          return app.el.createGroupDialog().classList.remove('hidden');
        };
      }).catch(function(err) {
        return tdbAlert(app._err(err), 'error');
      });
    },
    openChangePasswordDialog: function(app) {
      app.el.cpCurrent().value = '';
      app.el.cpNew().value = '';
      app.el.cpConfirm().value = '';
      app.el.cpError().textContent = '';
      return app.el.changePasswordDialog().classList.remove('hidden');
    },
    bindChangePasswordDialog: function(app) {
      app.el.cpCancelBtn().addEventListener('click', function() {
        return app.el.changePasswordDialog().classList.add('hidden');
      });
      app.el.changePasswordDialog().addEventListener('keydown', function(e) {
        if (e.key === 'Enter') {
          app.el.cpSubmitBtn().click();
        }
        if (e.key === 'Escape') {
          return app.el.changePasswordDialog().classList.add('hidden');
        }
      });
      return app.el.cpSubmitBtn().addEventListener('click', function() {
        var confirm, current, nw;
        current = app.el.cpCurrent().value;
        nw = app.el.cpNew().value;
        confirm = app.el.cpConfirm().value;
        app.el.cpError().textContent = '';
        if (!(current && nw)) {
          app.el.cpError().textContent = app._t('ui.validation.requiredAllFields');
          return;
        }
        if (nw !== confirm) {
          app.el.cpError().textContent = app._t('ui.validation.newPasswordsMismatch');
          return;
        }
        return Auth.changePassword(current, nw).then(function(ok) {
          if (ok) {
            localStorage.setItem('tdb_password_changed', '1');
            app.el.changePasswordDialog().classList.add('hidden');
            app.el.defaultPasswordWarning().classList.add('hidden');
            return tdbAlert(app._t('ui.alerts.passwordChangedSuccess'), 'info');
          } else {
            return app.el.cpError().textContent = app._t('ui.validation.currentPasswordIncorrect');
          }
        }).catch(function(err) {
          return app.el.cpError().textContent = app._err(err);
        });
      });
    },
    bindCreateUserDialog: function(app) {
      app.el.cuCancelBtn().addEventListener('click', function() {
        return app.el.createUserDialog().classList.add('hidden');
      });
      return app.el.cuSubmitBtn().addEventListener('click', function() {
        var email, password, username;
        username = app.el.cuUsername().value.trim();
        email = app.el.cuEmail().value.trim();
        password = app.el.cuPassword().value;
        app.el.cuError().textContent = '';
        if (!(username && password)) {
          app.el.cuError().textContent = app._t('ui.validation.usernamePasswordRequired');
          return;
        }
        return Auth.createUser(username, email || null, password).then(function() {
          app.el.createUserDialog().classList.add('hidden');
          app.el.cuUsername().value = '';
          app.el.cuEmail().value = '';
          app.el.cuPassword().value = '';
          return app._loadAdminUsers();
        }).catch(function(err) {
          return app.el.cuError().textContent = app._err(err);
        });
      });
    },
    bindCreateGroupDialog: function(app) {
      app.el.cgCancelBtn().addEventListener('click', function() {
        return app.el.createGroupDialog().classList.add('hidden');
      });
      return app.el.cgSubmitBtn().addEventListener('click', function() {
        var description, name;
        name = app.el.cgName().value.trim();
        description = app.el.cgDescription().value.trim();
        app.el.cgError().textContent = '';
        if (!name) {
          app.el.cgError().textContent = app._t('ui.validation.groupNameRequired');
          return;
        }
        return Auth.createGroup(name, description).then(function() {
          app.el.createGroupDialog().classList.add('hidden');
          app.el.cgName().value = '';
          app.el.cgDescription().value = '';
          return app._loadAdminGroups();
        }).catch(function(err) {
          return app.el.cgError().textContent = app._err(err);
        });
      });
    }
  };

}).call(this);
