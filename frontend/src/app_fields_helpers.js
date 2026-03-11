(function() {
  // app_fields_helpers.coffee — small UI helpers extracted from app.coffee
  window.AppFieldsHelpers = {
    bindFormulaFilter: function(app) {
      app._formulaTimer = null;
      return app.el.formulaFilterInput().addEventListener('input', function(e) {
        var val;
        clearTimeout(app._formulaTimer);
        val = e.target.value.trim();
        e.target.classList.toggle('active', val !== '');
        return app._formulaTimer = setTimeout(function() {
          var ref;
          return (ref = app._activeDataView) != null ? ref.setFormulaFilter(val) : void 0;
        }, 400);
      });
    },
    closeFieldsPanel: function(app) {
      app.el.fieldsPanel().classList.add('hidden');
      app.el.fieldsBtn().classList.remove('active');
      return app._refreshActiveDataViewLayout();
    },
    openFieldsPanel: function(app) {
      app.el.fieldsPanel().classList.remove('hidden');
      app.el.fieldsBtn().classList.add('active');
      return app.renderFieldsList().then(function() {
        var ref, selected;
        selected = app._selectedColumnName || ((ref = app._activeDataView) != null ? typeof ref.getFocusedColumnName === "function" ? ref.getFocusedColumnName() : void 0 : void 0);
        if (!selected) {
          return;
        }
        window.AppFieldsHelpers.highlightFieldInPanel(app, selected);
        return window.AppFieldsHelpers.openFieldEditorByName(app, selected);
      });
    },
    bindFieldsPanel: function(app) {
      var ref;
      app.el.fieldsBtn().addEventListener('click', function() {
        var panel;
        panel = app.el.fieldsPanel();
        if (panel.classList.contains('hidden')) {
          return window.AppFieldsHelpers.openFieldsPanel(app);
        } else {
          return window.AppFieldsHelpers.closeFieldsPanel(app);
        }
      });
      app.el.fieldsPanelClose().addEventListener('click', function() {
        return window.AppFieldsHelpers.closeFieldsPanel(app);
      });
      app.el.fieldType().addEventListener('change', function() {
        return app._onFieldTypeChange();
      });
      document.querySelectorAll('input[name="formula-type"]').forEach(function(radio) {
        return radio.addEventListener('change', function() {
          var val;
          val = document.querySelector('input[name="formula-type"]:checked').value;
          app.el.formulaBody().classList.toggle('hidden', val === 'none');
          return app.el.triggerFieldsRow().classList.toggle('hidden', val !== 'trigger');
        });
      });
      document.getElementById('formula-expand-btn').addEventListener('click', function() {
        var lang, ref;
        lang = ((ref = app.el.formulaLanguage()) != null ? ref.value : void 0) || 'lua';
        app.el.formulaModal().classList.remove('hidden');
        if (!app._cmFormula) {
          app._cmFormula = CodeMirror(document.getElementById('formula-cm-editor'), {
            mode: lang,
            theme: 'monokai',
            lineNumbers: true,
            lineWrapping: true,
            tabSize: 2,
            indentWithTabs: false
          });
        } else {
          app._cmFormula.setOption('mode', lang);
        }
        app._cmFormula.setValue(app.el.fieldFormula().value);
        return setTimeout((function() {
          return app._cmFormula.refresh();
        }), 10);
      });
      app.el.formulaModalApplyBtn().addEventListener('click', function() {
        if (app._cmFormula) {
          app.el.fieldFormula().value = app._cmFormula.getValue();
        }
        return app.el.formulaModal().classList.add('hidden');
      });
      app.el.formulaModalCloseBtn().addEventListener('click', function() {
        return app.el.formulaModal().classList.add('hidden');
      });
      if ((ref = app.el.formulaLanguage()) != null) {
        ref.addEventListener('change', function() {
          var ref1;
          return (ref1 = app._cmFormula) != null ? ref1.setOption('mode', app.el.formulaLanguage().value) : void 0;
        });
      }
      app.el.fieldCancelBtn().addEventListener('click', function() {
        return app._resetFieldForm();
      });
      return app.el.fieldAddBtn().addEventListener('click', function() {
        return window.AppFieldsHelpers.handleFieldSubmit(app);
      });
    },
    onGridColumnFocused: function(app, columnName) {
      if (!columnName) {
        return;
      }
      app._selectedColumnName = columnName;
      if (app.el.fieldsPanel().classList.contains('hidden')) {
        return;
      }
      this.highlightFieldInPanel(app, columnName);
      return this.openFieldEditorByName(app, columnName);
    },
    highlightFieldInPanel: function(app, fieldName) {
      var li, ul;
      ul = app.el.fieldsList();
      if (!ul) {
        return;
      }
      ul.querySelectorAll('li').forEach(function(el) {
        return el.classList.remove('selected');
      });
      li = ul.querySelector(`li[data-field-name='${fieldName}']`);
      if (!li) {
        return;
      }
      li.classList.add('selected');
      return li.scrollIntoView({
        block: 'nearest'
      });
    },
    openFieldEditorByName: function(app, fieldName) {
      var field, ref, relation;
      if (!(app._currentSpace && fieldName)) {
        return;
      }
      field = (app._currentSpace.fields || []).find(function(f) {
        return f.name === fieldName;
      });
      if (!field) {
        return;
      }
      relation = ((ref = app._fieldsRelMap) != null ? ref[field.id] : void 0) || null;
      return app._startEditField(field, relation);
    },
    onFieldTypeChange: function(app) {
      var formulaSection, i, isRelation, len, opt, ref, ref1, ref2, results, sel, sp, type;
      type = app.el.fieldType().value;
      isRelation = type === 'Relation';
      app.el.relTargetRow().classList.toggle('hidden', !isRelation);
      app.el.relReprRow().classList.toggle('hidden', !isRelation);
      if ((ref = app.el.fieldNotNull().closest('label')) != null) {
        ref.classList.toggle('hidden', isRelation);
      }
      formulaSection = app.el.formulaBody().closest('.formula-section');
      if (formulaSection != null) {
        formulaSection.classList.toggle('hidden', isRelation);
      }
      if ((ref1 = document.getElementById('field-repr-section')) != null) {
        ref1.classList.toggle('hidden', isRelation);
      }
      if (isRelation) {
        sel = app.el.relToSpace();
        sel.innerHTML = '<option value="">Cible…</option>';
        ref2 = app._allSpaces || [];
        results = [];
        for (i = 0, len = ref2.length; i < len; i++) {
          sp = ref2[i];
          opt = document.createElement('option');
          opt.value = sp.id;
          opt.textContent = sp.name;
          results.push(sel.appendChild(opt));
        }
        return results;
      }
    },
    resetFieldForm: function(app) {
      var formulaSection, ref;
      app._editingFieldId = null;
      app._editingRelation = null;
      app.el.fieldName().value = '';
      app.el.fieldType().value = 'String';
      app.el.fieldType().disabled = false;
      app.el.fieldNotNull().checked = false;
      app.el.fieldFormula().value = '';
      app.el.fieldTriggerFields().value = '';
      if (app.el.formulaLanguage()) {
        app.el.formulaLanguage().value = 'lua';
      }
      document.querySelector('input[name="formula-type"][value="none"]').checked = true;
      app.el.formulaBody().classList.add('hidden');
      app.el.triggerFieldsRow().classList.add('hidden');
      app.el.relTargetRow().classList.add('hidden');
      app.el.relReprRow().classList.add('hidden');
      app.el.relReprFormula().value = '';
      if (app.el.fieldReprFormula()) {
        app.el.fieldReprFormula().value = '';
      }
      if ((ref = app.el.fieldNotNull().closest('label')) != null) {
        ref.classList.remove('hidden');
      }
      formulaSection = app.el.formulaBody().closest('.formula-section');
      if (formulaSection != null) {
        formulaSection.classList.remove('hidden');
      }
      app.el.formulaModal().classList.add('hidden');
      app.el.fieldAddBtn().textContent = app._t('ui.fields.add');
      return app.el.fieldCancelBtn().classList.add('hidden');
    },
    parseTriggerFields: function(raw) {
      var i, len, ref, results, s;
      if (raw === '*') {
        return ['*'];
      }
      if (raw === '') {
        return [];
      }
      ref = raw.split(',');
      results = [];
      for (i = 0, len = ref.length; i < len; i++) {
        s = ref[i];
        if (s.trim()) {
          results.push(s.trim());
        }
      }
      return results;
    },
    applyFormulaOptions: function(app, opts, formulaType, emptyFormulaValue = '') {
      var raw, ref;
      if (formulaType !== 'none') {
        opts.formula = app.el.fieldFormula().value.trim() || null;
        opts.language = ((ref = app.el.formulaLanguage()) != null ? ref.value : void 0) || 'lua';
        if (formulaType === 'trigger' && opts.formula) {
          raw = app.el.fieldTriggerFields().value.trim();
          opts.triggerFields = this.parseTriggerFields(raw);
        } else {
          opts.triggerFields = null;
        }
      } else {
        opts.formula = emptyFormulaValue;
        opts.triggerFields = null;
        opts.language = 'lua';
      }
      return opts;
    },
    startEditField: function(app, field, relation = null) {
      var tf;
      app._editingFieldId = field.id;
      app._editingRelation = relation || null;
      app.el.fieldAddBtn().textContent = app._t('ui.fields.update');
      app.el.fieldCancelBtn().classList.remove('hidden');
      app.el.fieldType().disabled = false;
      app.el.fieldName().value = field.name;
      if (relation) {
        app.el.fieldType().value = 'Relation';
        app._onFieldTypeChange();
        app.el.relReprFormula().value = relation.reprFormula || '';
        app.el.relToSpace().value = relation.toSpaceId || '';
        if (app.el.fieldReprFormula()) {
          app.el.fieldReprFormula().value = '';
        }
      } else {
        app.el.fieldType().value = field.fieldType;
        app._onFieldTypeChange();
        app.el.fieldNotNull().checked = field.notNull;
        if (app.el.fieldReprFormula()) {
          app.el.fieldReprFormula().value = field.reprFormula || '';
        }
        if (field.formula && field.formula !== '') {
          if (field.triggerFields) {
            document.querySelector('input[name="formula-type"][value="trigger"]').checked = true;
            app.el.triggerFieldsRow().classList.remove('hidden');
            tf = field.triggerFields;
            app.el.fieldTriggerFields().value = tf.length === 0 ? '' : tf[0] === '*' ? '*' : tf.join(', ');
          } else {
            document.querySelector('input[name="formula-type"][value="formula"]').checked = true;
          }
          app.el.formulaBody().classList.remove('hidden');
          app.el.fieldFormula().value = field.formula;
          if (app.el.formulaLanguage()) {
            app.el.formulaLanguage().value = field.language || 'lua';
          }
        } else {
          document.querySelector('input[name="formula-type"][value="none"]').checked = true;
          app.el.formulaBody().classList.add('hidden');
        }
      }
      return app.el.fieldName().focus();
    },
    updateFieldProperties: function(app, fieldId, opts, formulaType) {
      var editRelation, ref, relReprFormula, updatePromise;
      window.AppFieldsHelpers.applyFormulaOptions(app, opts, formulaType, '');
      opts.reprFormula = ((ref = app.el.fieldReprFormula()) != null ? ref.value.trim() : void 0) || '';
      editRelation = app._editingRelation;
      relReprFormula = app.el.relReprFormula().value.trim();
      updatePromise = Spaces.updateField(fieldId, opts);
      if (editRelation) {
        updatePromise = updatePromise.then(function() {
          return Spaces.updateRelation(editRelation.id, relReprFormula);
        });
      }
      return updatePromise.then(function() {
        return Spaces.getWithFields(app._currentSpace.id).then(function(full) {
          app._currentSpace = full;
          app._syncSpaceFields(full);
          app.renderFieldsList();
          app._mountDataView(full);
          return app._resetFieldForm();
        });
      }).catch(function(err) {
        return tdbAlert(app._err(err), 'error');
      });
    },
    renderFieldsList: function(app) {
      var fields, ul;
      if (!app._currentSpace) {
        return;
      }
      ul = app.el.fieldsList();
      ul.innerHTML = '';
      fields = app._currentSpace.fields || [];
      return Spaces.listRelations(app._currentSpace.id).then(function(relations) {
        var badge, del, dragSrc, editBtn, f, fb, handle, i, j, k, langLabel, len, len1, len2, li, name, r, ref, ref1, rel, relMap, req, results, sp, spaceMap, targetName, triggerDesc;
        relMap = {};
        spaceMap = {};
        ref = app._allSpaces;
        for (i = 0, len = ref.length; i < len; i++) {
          sp = ref[i];
          spaceMap[sp.id] = sp.name;
        }
        ref1 = relations || [];
        for (j = 0, len1 = ref1.length; j < len1; j++) {
          r = ref1[j];
          relMap[r.fromFieldId] = r;
        }
        app._fieldsRelMap = relMap;
        if (fields.length === 0) {
          li = document.createElement('li');
          li.textContent = app._t('ui.fields.noneDefined');
          li.style.color = '#aaa';
          ul.appendChild(li);
          return;
        }
        dragSrc = null;
        results = [];
        for (k = 0, len2 = fields.length; k < len2; k++) {
          f = fields[k];
          li = document.createElement('li');
          li.draggable = true;
          li.dataset.fieldId = f.id;
          li.dataset.fieldName = f.name;
          li.style.cursor = 'grab';
          handle = document.createElement('span');
          handle.textContent = '⠿';
          handle.title = app._t('ui.fields.dragToReorder');
          handle.style.cssText = 'margin-right:.4rem;color:#888;cursor:grab;user-select:none;';
          rel = relMap[f.id];
          badge = document.createElement('span');
          badge.className = 'field-type-badge';
          if (rel) {
            targetName = spaceMap[rel.toSpaceId] || rel.toSpaceId;
            badge.textContent = `→ ${targetName}`;
            badge.title = `Relation vers ${targetName}`;
          } else {
            badge.textContent = f.fieldType;
          }
          name = document.createElement('span');
          name.textContent = ` ${f.name} `;
          name.style.flex = '1';
          if (f.notNull) {
            req = document.createElement('span');
            req.className = 'field-required';
            req.title = 'Requis';
            req.textContent = '*';
            name.appendChild(req);
          }
          if (f.formula && f.formula !== '' && !rel) {
            fb = document.createElement('span');
            langLabel = f.language === 'moonscript' ? ' [moon]' : '';
            if (f.triggerFields) {
              fb.className = 'field-trigger-badge';
              triggerDesc = f.triggerFields.length === 0 ? app._t('ui.fields.triggerCreation') : f.triggerFields[0] === '*' ? app._t('ui.fields.triggerAnyChange') : f.triggerFields.join(', ');
              fb.textContent = '⚡';
              fb.title = `Trigger formula${langLabel} (${triggerDesc}) : ${f.formula}`;
            } else {
              fb.className = 'field-formula-badge';
              fb.textContent = 'λ';
              fb.title = `${app._t('ui.fields.computedColumn')}${langLabel} : ${f.formula}`;
            }
            name.appendChild(fb);
          }
          editBtn = document.createElement('button');
          editBtn.textContent = '✎';
          editBtn.title = 'Modifier ce champ';
          editBtn.style.cssText = 'background:none;border:none;cursor:pointer;color:#888;font-size:.9rem;margin-left:.2rem;';
          (function(field, relation) {
            return editBtn.addEventListener('click', function() {
              window.AppFieldsHelpers.highlightFieldInPanel(app, field.name);
              return window.AppFieldsHelpers.startEditField(app, field, relation);
            });
          })(f, rel);
          del = document.createElement('button');
          del.textContent = '✕';
          del.title = 'Supprimer ce champ';
          del.style.cssText = 'margin-left:.2rem;background:none;border:none;cursor:pointer;color:#aaa;font-size:.9rem;';
          (function(fieldId, fieldName, relation) {
            return del.addEventListener('click', async function() {
              var doDelete;
              if (!(await tdbConfirm(app._t('ui.confirms.deleteField', {
                name: fieldName
              })))) {
                return;
              }
              doDelete = function() {
                return GQL.mutate(app._removeFieldMutation, {fieldId}).then(function() {
                  return Spaces.getWithFields(app._currentSpace.id).then(function(full) {
                    app._currentSpace = full;
                    app._syncSpaceFields(full);
                    app.renderFieldsList();
                    return app._mountDataView(full);
                  });
                }).catch(function(err) {
                  return tdbAlert(app._err(err), 'error');
                });
              };
              if (relation) {
                return Spaces.deleteRelation(relation.id).then(doDelete).catch(function(err) {
                  return tdbAlert(app._err(err), 'error');
                });
              } else {
                return doDelete();
              }
            });
          })(f.id, f.name, rel);
          li.appendChild(handle);
          li.appendChild(badge);
          li.appendChild(name);
          li.appendChild(editBtn);
          li.appendChild(del);
          li.addEventListener('dragstart', function(e) {
            dragSrc = this;
            e.dataTransfer.effectAllowed = 'move';
            e.dataTransfer.setData('text/plain', this.dataset.fieldId);
            return setTimeout((() => {
              return this.classList.add('dragging');
            }), 0);
          });
          li.addEventListener('dragend', function() {
            this.classList.remove('dragging');
            return ul.querySelectorAll('li').forEach(function(el) {
              return el.classList.remove('drag-over');
            });
          });
          li.addEventListener('dragover', function(e) {
            e.preventDefault();
            e.dataTransfer.dropEffect = 'move';
            ul.querySelectorAll('li').forEach(function(el) {
              return el.classList.remove('drag-over');
            });
            if (this !== dragSrc) {
              return this.classList.add('drag-over');
            }
          });
          li.addEventListener('drop', function(e) {
            var insertBefore, newOrder, rect, target;
            e.preventDefault();
            target = e.currentTarget;
            if (dragSrc === target) {
              return;
            }
            rect = target.getBoundingClientRect();
            insertBefore = e.clientY < rect.top + rect.height / 2;
            if (insertBefore) {
              ul.insertBefore(dragSrc, target);
            } else {
              target.after(dragSrc);
            }
            newOrder = Array.from(ul.querySelectorAll('li')).map(function(el) {
              return el.dataset.fieldId;
            });
            return GQL.mutate(app._reorderFieldsMutation, {
              spaceId: app._currentSpace.id,
              fieldIds: newOrder
            }).then(function(res) {
              app._currentSpace.fields = res.reorderFields;
              app._syncSpaceFields(app._currentSpace);
              app.renderFieldsList();
              return app._mountDataView(app._currentSpace);
            }).catch(function(err) {
              return tdbAlert(app._err(err), 'error');
            });
          });
          results.push(ul.appendChild(li));
        }
        return results;
      });
    },
    handleFieldSubmit: function(app) {
      var conversionFormula, conversionLang, formulaOpts, formulaType, name, notNull, opts, originalField, originalType, ref, ref1, ref2, reprFormula, toSpaceId, type;
      if (!app._currentSpace) {
        return;
      }
      name = app.el.fieldName().value.trim();
      type = app.el.fieldType().value;
      notNull = app.el.fieldNotNull().checked;
      if (!name) {
        app.el.fieldName().classList.add('input-error');
        app.el.fieldName().placeholder = app._t('ui.validation.groupNameRequired');
        app.el.fieldName().focus();
        return;
      }
      app.el.fieldName().classList.remove('input-error');
      app.el.fieldName().placeholder = app._t('ui.fields.namePlaceholder');
      if (app._editingFieldId) {
        originalField = (((ref = app._currentSpace) != null ? ref.fields : void 0) || []).find(function(f) {
          return f.id === app._editingFieldId;
        });
        originalType = originalField != null ? originalField.fieldType : void 0;
        formulaType = document.querySelector('input[name="formula-type"]:checked').value;
        opts = {name, notNull};
        if (type !== originalType) {
          conversionFormula = null;
          conversionLang = 'lua';
          if (formulaType !== 'none') {
            conversionFormula = app.el.fieldFormula().value.trim() || null;
            conversionLang = ((ref1 = app.el.formulaLanguage()) != null ? ref1.value : void 0) || 'lua';
          }
          return Spaces.changeFieldType(app._editingFieldId, type, conversionFormula, conversionLang).then(function() {
            var reprFormula, toSpaceId;
            if (type === 'Relation') {
              toSpaceId = app.el.relToSpace().value;
              reprFormula = app.el.relReprFormula().value.trim();
              if (!toSpaceId) {
                return;
              }
              return Spaces.getWithFields(toSpaceId).then(function(targetSpace) {
                var idField;
                idField = (targetSpace.fields || []).find(function(f) {
                  return f.fieldType === 'Sequence';
                });
                if (!idField) {
                  tdbAlert(app._t('ui.alerts.targetNoSequence'), 'warn');
                  return;
                }
                return Spaces.createRelation(`${app._currentSpace.name}_${app.el.fieldName().value}_rel`, app._currentSpace.id, app._editingFieldId, toSpaceId, idField.id, reprFormula);
              });
            } else {
              return app.updateFieldProperties(app._editingFieldId, opts, formulaType);
            }
          }).catch(function(err) {
            return tdbAlert(app._err(err), 'error');
          });
        } else {
          return app.updateFieldProperties(app._editingFieldId, opts, formulaType);
        }
      } else if (type === 'Relation') {
        toSpaceId = app.el.relToSpace().value;
        reprFormula = app.el.relReprFormula().value.trim();
        if (!toSpaceId) {
          return;
        }
        Spaces.getWithFields(toSpaceId).then(function(targetSpace) {
          var idField;
          idField = (targetSpace.fields || []).find(function(f) {
            return f.fieldType === 'Sequence';
          });
          if (!idField) {
            tdbAlert(app._t('ui.alerts.targetNoSequence'), 'warn');
            return;
          }
          return Spaces.addField(app._currentSpace.id, name, 'Int', notNull, '').then(function(newField) {
            return Spaces.createRelation(name, app._currentSpace.id, newField.id, toSpaceId, idField.id, reprFormula).then(function() {
              return Spaces.getWithFields(app._currentSpace.id).then(function(full) {
                app._currentSpace = full;
                app._syncSpaceFields(full);
                app.renderFieldsList();
                return app._mountDataView(full);
              });
            }).catch(function(err) {
              return tdbAlert(app._err(err), 'error');
            });
          }).catch(function(err) {
            return tdbAlert(app._err(err), 'error');
          });
        });
        return app._resetFieldForm();
      } else {
        formulaType = document.querySelector('input[name="formula-type"]:checked').value;
        formulaOpts = window.AppFieldsHelpers.applyFormulaOptions(app, {}, formulaType, null);
        reprFormula = ((ref2 = app.el.fieldReprFormula()) != null ? ref2.value.trim() : void 0) || null;
        Spaces.addField(app._currentSpace.id, name, type, notNull, '', formulaOpts.formula, formulaOpts.triggerFields, formulaOpts.language, reprFormula).then(function() {
          return Spaces.getWithFields(app._currentSpace.id).then(function(full) {
            app._currentSpace = full;
            app._syncSpaceFields(full);
            app.renderFieldsList();
            return app._mountDataView(full);
          });
        }).catch(function(err) {
          return tdbAlert(app._err(err), 'error');
        });
        return app._resetFieldForm();
      }
    }
  };

}).call(this);
