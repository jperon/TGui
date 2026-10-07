(function() {
  // app_view_helpers_pages.coffee — page list helpers extracted from app_view_helpers.coffee
  Object.assign(window.AppViewHelpers, {
    loadPages: function(app) {
      return GQL.query(app._listCustomViewsQuery).then(function(data) {
        return app.renderPageList(data.customViews);
      }).catch(function(err) {
        return tdbAlert(app._err(err), 'error');
      });
    },
    renderPageList: function(app, views) {
      var base, curr, cv, dictName, i, j, len, len1, parts, ref, ref1, renderTree, tree, ul;
      ul = app.el.pageList();
      ul.innerHTML = '';
      tree = {
        items: [],
        folders: {}
      };
      ref = views || [];
      for (i = 0, len = ref.length; i < len; i++) {
        cv = ref[i];
        parts = cv.name.split('/');
        curr = tree;
        ref1 = parts.slice(0, -1);
        for (j = 0, len1 = ref1.length; j < len1; j++) {
          dictName = ref1[j];
          if ((base = curr.folders)[dictName] == null) {
            base[dictName] = {
              items: [],
              folders: {}
            };
          }
          curr = curr.folders[dictName];
        }
        curr.items.push({
          cv: cv,
          shortName: parts[parts.length - 1]
        });
      }
      renderTree = function(node, containerEl, pathStr = "") {
        var btnExport, btnGroup, btnImport, fName, fNode, folderLi, folderNames, fullPath, header, icon, inputFile, item, k, l, len2, len3, li, lsKey, results, sortedItems, spanName, subUl;
        folderNames = Object.keys(node.folders).sort(function(a, b) {
          return a.toLowerCase().localeCompare(b.toLowerCase());
        });
        for (k = 0, len2 = folderNames.length; k < len2; k++) {
          fName = folderNames[k];
          fNode = node.folders[fName];
          fullPath = pathStr ? `${pathStr}/${fName}` : fName;
          folderLi = document.createElement('li');
          folderLi.className = 'folder-item';
          header = document.createElement('div');
          header.className = 'folder-header';
          icon = document.createElement('span');
          icon.className = 'folder-toggle-icon';
          icon.textContent = '▾';
          header.appendChild(icon);
          header.appendChild(document.createTextNode(` ${fName}`));
          folderLi.appendChild(header);
          subUl = document.createElement('ul');
          subUl.className = 'folder-children';
          folderLi.appendChild(subUl);
          lsKey = `tdb_folder_page_${fullPath}`;
          if (localStorage.getItem(lsKey) === 'true') {
            folderLi.classList.add('collapsed');
          }
          header.addEventListener('click', function(e) {
            var isCollapsed;
            e.stopPropagation();
            isCollapsed = folderLi.classList.toggle('collapsed');
            return localStorage.setItem(lsKey, isCollapsed ? 'true' : 'false');
          });
          renderTree(fNode, subUl, fullPath);
          containerEl.appendChild(folderLi);
        }
        sortedItems = node.items.sort(function(a, b) {
          return a.shortName.toLowerCase().localeCompare(b.shortName.toLowerCase());
        });
        results = [];
        for (l = 0, len3 = sortedItems.length; l < len3; l++) {
          item = sortedItems[l];
          li = document.createElement('li');
          li.className = 'leaf-item';
          li.dataset.id = item.cv.id;
          li.title = item.cv.name;
          spanName = document.createElement('span');
          spanName.className = 'leaf-item-name';
          spanName.textContent = item.shortName;
          li.appendChild(spanName);
          btnGroup = document.createElement('span');
          btnGroup.className = 'leaf-item-actions';
          btnExport = document.createElement('button');
          btnExport.className = 'toolbar-btn toolbar-btn--icon page-action-btn';
          btnExport.title = 'Exporter le layout';
          btnExport.textContent = '↓';
          btnExport.addEventListener('click', function(e) {
            e.stopPropagation();
            return GQL.query('query ExportLayout($pageId: ID!) { exportLayout(pageId: $pageId) }', {
              pageId: item.cv.id
            }).then(function(data) {
              var a, blob, url;
              blob = new Blob([data.exportLayout], {
                type: 'text/yaml'
              });
              url = URL.createObjectURL(blob);
              a = document.createElement('a');
              a.href = url;
              a.download = `${item.cv.name.replace(/[^a-z0-9]/gi, '_')}.yaml`;
              a.click();
              return URL.revokeObjectURL(url);
            }).catch(function(err) {
              return tdbAlert(app._err(err), 'error');
            });
          });
          btnGroup.appendChild(btnExport);
          btnImport = document.createElement('button');
          btnImport.className = 'toolbar-btn toolbar-btn--icon page-action-btn';
          btnImport.title = 'Importer un layout';
          btnImport.textContent = '↑';
          inputFile = null;
          btnImport.addEventListener('click', function(e) {
            e.stopPropagation();
            inputFile = document.createElement('input');
            inputFile.type = 'file';
            inputFile.accept = '.yaml,.yml';
            inputFile.onchange = function(evt) {
              var file, reader;
              file = evt.target.files[0];
              if (!file) {
                return;
              }
              reader = new FileReader();
              reader.onload = function(e) {
                var yaml;
                yaml = e.target.result;
                return GQL.mutate('mutation ImportLayout($pageId: ID!, $yaml: String!) { importLayout(pageId: $pageId, yaml: $yaml) { id name yaml } }', {
                  pageId: item.cv.id,
                  yaml
                }).then(function() {
                  return app.loadPages();
                }).catch(function(err) {
                  return tdbAlert(app._err(err), 'error');
                });
              };
              return reader.readAsText(file);
            };
            return inputFile.click();
          });
          btnGroup.appendChild(btnImport);
          li.appendChild(btnGroup);
          (function(cv) {
            return li.addEventListener('click', function(e) {
              e.stopPropagation();
              return app.selectPage(cv);
            });
          })(item.cv);
          results.push(containerEl.appendChild(li));
        }
        return results;
      };
      return renderTree(tree, ul);
    },
    selectPage: function(app, cv) {
      var i, j, len, len1, li, panel, parent, ref, ref1, ref2, ref3, ref4;
      history.replaceState(null, '', `#page/${cv.id}`);
      app._currentCustomView = cv;
      ref = app.el.spaceList().querySelectorAll('li');
      for (i = 0, len = ref.length; i < len; i++) {
        li = ref[i];
        li.classList.remove('active');
      }
      ref1 = app.el.pageList().querySelectorAll('.leaf-item');
      for (j = 0, len1 = ref1.length; j < len1; j++) {
        li = ref1[j];
        li.classList.toggle('active', li.dataset.id === cv.id);
        if (li.dataset.id === cv.id) {
          parent = li.parentElement;
          while (parent && parent.id !== 'page-list') {
            if (parent.tagName === 'LI' && parent.classList.contains('folder-item')) {
              parent.classList.remove('collapsed');
            }
            parent = parent.parentElement;
          }
        }
      }
      app._currentSpace = null;
      if ((ref2 = app._activeDataView) != null) {
        if (typeof ref2.unmount === "function") {
          ref2.unmount();
        }
      }
      app._activeDataView = null;
      app.el.dataToolbar().classList.add('hidden');
      app.el.fieldsPanel().classList.add('hidden');
      app.el.gridContainer().classList.add('hidden');
      app.el.welcome().classList.add('hidden');
      app.el.adminPanel().classList.add('hidden');
      app.el.contentRow().classList.remove('hidden');
      panel = app.el.yamlEditorPanel();
      panel.classList.remove('hidden');
      app.el.yamlPageName().textContent = cv.name;
      if ((ref3 = cv.yaml) != null ? ref3.trim() : void 0) {
        app._renderCustomViewPreview(cv.yaml);
      } else {
        app._openYamlModal();
      }
      return (ref4 = window.AppUndoHelpers) != null ? typeof ref4.refreshUI === "function" ? ref4.refreshUI(app) : void 0 : void 0;
    }
  });

}).call(this);
