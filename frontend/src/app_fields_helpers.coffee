# app_fields_helpers.coffee — small UI helpers extracted from app.coffee

window.AppFieldsHelpers =
  bindFormulaFilter: (app) ->
    app._formulaTimer = null
    app.el.formulaFilterInput().addEventListener 'input', (e) ->
      clearTimeout app._formulaTimer
      val = e.target.value.trim()
      e.target.classList.toggle 'active', val != ''
      app._formulaTimer = setTimeout ->
        app._activeDataView?.setFormulaFilter val
      , 400

  closeFieldsPanel: (app) ->
    app.el.fieldsPanel().classList.add 'hidden'
    app.el.fieldsBtn().classList.remove 'active'
    app._refreshActiveDataViewLayout()

  openFieldsPanel: (app) ->
    app.el.fieldsPanel().classList.remove 'hidden'
    app.el.fieldsBtn().classList.add 'active'
    app.renderFieldsList().then ->
      selected = app._selectedColumnName or app._activeDataView?.getFocusedColumnName?()
      return unless selected
      window.AppFieldsHelpers.highlightFieldInPanel app, selected
      window.AppFieldsHelpers.openFieldEditorByName app, selected

  bindFieldsPanel: (app) ->
    app.el.fieldsBtn().addEventListener 'click', ->
      panel = app.el.fieldsPanel()
      if panel.classList.contains 'hidden'
        window.AppFieldsHelpers.openFieldsPanel app
      else
        window.AppFieldsHelpers.closeFieldsPanel app

    app.el.fieldsPanelClose().addEventListener 'click', ->
      window.AppFieldsHelpers.closeFieldsPanel app

    app.el.fieldType().addEventListener 'change', ->
      app._onFieldTypeChange()

    document.querySelectorAll('input[name="formula-type"]').forEach (radio) ->
      radio.addEventListener 'change', ->
        val = document.querySelector('input[name="formula-type"]:checked').value
        app.el.formulaBody().classList.toggle 'hidden', val == 'none'
        app.el.triggerFieldsRow().classList.toggle 'hidden', val != 'trigger'

    document.getElementById('formula-expand-btn').addEventListener 'click', ->
      lang = app.el.formulaLanguage()?.value or 'lua'
      app.el.formulaModal().classList.remove 'hidden'
      unless app._cmFormula
        app._cmFormula = CodeMirror document.getElementById('formula-cm-editor'),
          mode: lang
          theme: 'monokai'
          lineNumbers: true
          lineWrapping: true
          tabSize: 2
          indentWithTabs: false
      else
        app._cmFormula.setOption 'mode', lang
      app._cmFormula.setValue app.el.fieldFormula().value
      setTimeout (-> app._cmFormula.refresh()), 10

    app.el.formulaModalApplyBtn().addEventListener 'click', ->
      app.el.fieldFormula().value = app._cmFormula.getValue() if app._cmFormula
      app.el.formulaModal().classList.add 'hidden'

    app.el.formulaModalCloseBtn().addEventListener 'click', ->
      app.el.formulaModal().classList.add 'hidden'

    app.el.formulaLanguage()?.addEventListener 'change', ->
      app._cmFormula?.setOption 'mode', app.el.formulaLanguage().value

    app.el.fieldCancelBtn().addEventListener 'click', ->
      app._resetFieldForm()

    app.el.fieldAddBtn().addEventListener 'click', ->
      window.AppFieldsHelpers.handleFieldSubmit app

  onGridColumnFocused: (app, columnName) ->
    return unless columnName
    app._selectedColumnName = columnName
    return if app.el.fieldsPanel().classList.contains 'hidden'
    @highlightFieldInPanel app, columnName
    @openFieldEditorByName app, columnName

  highlightFieldInPanel: (app, fieldName) ->
    ul = app.el.fieldsList()
    return unless ul
    ul.querySelectorAll('li').forEach (el) -> el.classList.remove 'selected'
    li = ul.querySelector "li[data-field-name='#{fieldName}']"
    return unless li
    li.classList.add 'selected'
    li.scrollIntoView { block: 'nearest' }

  openFieldEditorByName: (app, fieldName) ->
    return unless app._currentSpace and fieldName
    field = (app._currentSpace.fields or []).find (f) -> f.name == fieldName
    return unless field
    relation = app._fieldsRelMap?[field.id] or null
    app._startEditField field, relation

  onFieldTypeChange: (app) ->
    type = app.el.fieldType().value
    isRelation = type == 'Relation'
    app.el.relTargetRow().classList.toggle 'hidden', !isRelation
    app.el.relReprRow().classList.toggle 'hidden', !isRelation
    app.el.fieldNotNull().closest('label')?.classList.toggle 'hidden', isRelation
    formulaSection = app.el.formulaBody().closest('.formula-section')
    formulaSection?.classList.toggle 'hidden', isRelation
    document.getElementById('field-repr-section')?.classList.toggle 'hidden', isRelation
    if isRelation
      sel = app.el.relToSpace()
      sel.innerHTML = '<option value="">Cible…</option>'
      for sp in (app._allSpaces or [])
        opt = document.createElement 'option'
        opt.value = sp.id
        opt.textContent = sp.name
        sel.appendChild opt

  resetFieldForm: (app) ->
    app._editingFieldId = null
    app._editingRelation = null
    app.el.fieldName().value = ''
    app.el.fieldType().value = 'String'
    app.el.fieldType().disabled = false
    app.el.fieldNotNull().checked = false
    app.el.fieldFormula().value = ''
    app.el.fieldTriggerFields().value = ''
    if app.el.formulaLanguage() then app.el.formulaLanguage().value = 'lua'
    document.querySelector('input[name="formula-type"][value="none"]').checked = true
    app.el.formulaBody().classList.add 'hidden'
    app.el.triggerFieldsRow().classList.add 'hidden'
    app.el.relTargetRow().classList.add 'hidden'
    app.el.relReprRow().classList.add 'hidden'
    app.el.relReprFormula().value = ''
    app.el.fieldReprFormula().value = '' if app.el.fieldReprFormula()
    app.el.fieldNotNull().closest('label')?.classList.remove 'hidden'
    formulaSection = app.el.formulaBody().closest('.formula-section')
    formulaSection?.classList.remove 'hidden'
    app.el.formulaModal().classList.add 'hidden'
    app.el.fieldAddBtn().textContent = app._t('ui.fields.add')
    app.el.fieldCancelBtn().classList.add 'hidden'

  parseTriggerFields: (raw) ->
    return ['*'] if raw == '*'
    return [] if raw == ''
    (s.trim() for s in raw.split(',') when s.trim())

  applyFormulaOptions: (app, opts, formulaType, emptyFormulaValue = '') ->
    if formulaType != 'none'
      opts.formula  = app.el.fieldFormula().value.trim() or null
      opts.language = app.el.formulaLanguage()?.value or 'lua'
      if formulaType == 'trigger' and opts.formula
        raw = app.el.fieldTriggerFields().value.trim()
        opts.triggerFields = @parseTriggerFields raw
      else
        opts.triggerFields = null
    else
      opts.formula = emptyFormulaValue
      opts.triggerFields = null
      opts.language = 'lua'
    opts

  startEditField: (app, field, relation = null) ->
    app._editingFieldId = field.id
    app._editingRelation = relation or null
    app.el.fieldAddBtn().textContent = app._t('ui.fields.update')
    app.el.fieldCancelBtn().classList.remove 'hidden'
    app.el.fieldType().disabled = false
    app.el.fieldName().value = field.name
    if relation
      app.el.fieldType().value = 'Relation'
      app._onFieldTypeChange()
      app.el.relReprFormula().value = relation.reprFormula or ''
      app.el.relToSpace().value = relation.toSpaceId or ''
      app.el.fieldReprFormula().value = '' if app.el.fieldReprFormula()
    else
      app.el.fieldType().value = field.fieldType
      app._onFieldTypeChange()
      app.el.fieldNotNull().checked = field.notNull
      app.el.fieldReprFormula().value = field.reprFormula or '' if app.el.fieldReprFormula()
      if field.formula and field.formula != ''
        if field.triggerFields
          document.querySelector('input[name="formula-type"][value="trigger"]').checked = true
          app.el.triggerFieldsRow().classList.remove 'hidden'
          tf = field.triggerFields
          app.el.fieldTriggerFields().value =
            if tf.length == 0 then ''
            else if tf[0] == '*' then '*'
            else tf.join(', ')
        else
          document.querySelector('input[name="formula-type"][value="formula"]').checked = true
        app.el.formulaBody().classList.remove 'hidden'
        app.el.fieldFormula().value = field.formula
        if app.el.formulaLanguage() then app.el.formulaLanguage().value = field.language or 'lua'
      else
        document.querySelector('input[name="formula-type"][value="none"]').checked = true
        app.el.formulaBody().classList.add 'hidden'
    app.el.fieldName().focus()

  updateFieldProperties: (app, fieldId, opts, formulaType) ->
    window.AppFieldsHelpers.applyFormulaOptions app, opts, formulaType, ''
    opts.reprFormula = app.el.fieldReprFormula()?.value.trim() or ''

    editRelation = app._editingRelation
    relReprFormula  = app.el.relReprFormula().value.trim()
    updatePromise = Spaces.updateField(fieldId, opts)
    if editRelation
      updatePromise = updatePromise.then ->
        Spaces.updateRelation(editRelation.id, relReprFormula)
    updatePromise
      .then ->
        Spaces.getWithFields(app._currentSpace.id).then (full) ->
          app._currentSpace = full
          app._syncSpaceFields full
          app.renderFieldsList()
          app._mountDataView full
          app._resetFieldForm()
      .catch (err) -> tdbAlert app._err(err), 'error'

  renderFieldsList: (app) ->
    return unless app._currentSpace
    ul = app.el.fieldsList()
    ul.innerHTML = ''
    fields = app._currentSpace.fields or []
    Spaces.listRelations(app._currentSpace.id).then (relations) ->
      relMap = {}
      spaceMap = {}

      for sp in app._allSpaces
        spaceMap[sp.id] = sp.name

      for r in (relations or [])
        relMap[r.fromFieldId] = r
      app._fieldsRelMap = relMap

      if fields.length == 0
        li = document.createElement 'li'
        li.textContent = app._t('ui.fields.noneDefined')
        li.style.color = '#aaa'
        ul.appendChild li
        return

      dragSrc = null
      for f in fields
        li = document.createElement 'li'
        li.draggable = true
        li.dataset.fieldId = f.id
        li.dataset.fieldName = f.name
        li.style.cursor = 'grab'

        handle = document.createElement 'span'
        handle.textContent = '⠿'
        handle.title = app._t('ui.fields.dragToReorder')
        handle.style.cssText = 'margin-right:.4rem;color:#888;cursor:grab;user-select:none;'

        rel = relMap[f.id]
        badge = document.createElement 'span'
        badge.className = 'field-type-badge'
        if rel
          targetName = spaceMap[rel.toSpaceId] or rel.toSpaceId
          badge.textContent = "→ #{targetName}"
          badge.title = "Relation vers #{targetName}"
        else
          badge.textContent = f.fieldType

        name = document.createElement 'span'
        name.textContent = " #{f.name} "
        name.style.flex = '1'
        if f.notNull
          req = document.createElement 'span'
          req.className = 'field-required'
          req.title = 'Requis'
          req.textContent = '*'
          name.appendChild req
        if f.formula and f.formula != '' and not rel
          fb = document.createElement 'span'
          langLabel = if f.language == 'moonscript' then ' [moon]' else ''
          if f.triggerFields
            fb.className = 'field-trigger-badge'
            triggerDesc =
              if f.triggerFields.length == 0 then app._t('ui.fields.triggerCreation')
              else if f.triggerFields[0] == '*' then app._t('ui.fields.triggerAnyChange')
              else f.triggerFields.join(', ')
            fb.textContent = '⚡'
            fb.title = "Trigger formula#{langLabel} (#{triggerDesc}) : #{f.formula}"
          else
            fb.className = 'field-formula-badge'
            fb.textContent = 'λ'
            fb.title = "#{app._t('ui.fields.computedColumn')}#{langLabel} : #{f.formula}"
          name.appendChild fb

        editBtn = document.createElement 'button'
        editBtn.textContent = '✎'
        editBtn.title = 'Modifier ce champ'
        editBtn.style.cssText = 'background:none;border:none;cursor:pointer;color:#888;font-size:.9rem;margin-left:.2rem;'
        do (field = f, relation = rel) ->
          editBtn.addEventListener 'click', ->
            window.AppFieldsHelpers.highlightFieldInPanel app, field.name
            window.AppFieldsHelpers.startEditField app, field, relation

        del = document.createElement 'button'
        del.textContent = '✕'
        del.title = 'Supprimer ce champ'
        del.style.cssText = 'margin-left:.2rem;background:none;border:none;cursor:pointer;color:#aaa;font-size:.9rem;'
        do (fieldId = f.id, fieldName = f.name, relation = rel) ->
          del.addEventListener 'click', ->
            return unless await tdbConfirm app._t('ui.confirms.deleteField', { name: fieldName })
            doDelete = ->
              GQL.mutate(app._removeFieldMutation, { fieldId })
                .then ->
                  Spaces.getWithFields(app._currentSpace.id).then (full) ->
                    app._currentSpace = full
                    app._syncSpaceFields full
                    app.renderFieldsList()
                    app._mountDataView full
                .catch (err) -> tdbAlert app._err(err), 'error'
            if relation
              Spaces.deleteRelation(relation.id).then(doDelete).catch (err) -> tdbAlert app._err(err), 'error'
            else
              doDelete()

        li.appendChild handle
        li.appendChild badge
        li.appendChild name
        li.appendChild editBtn
        li.appendChild del

        li.addEventListener 'dragstart', (e) ->
          dragSrc = @
          e.dataTransfer.effectAllowed = 'move'
          e.dataTransfer.setData 'text/plain', @dataset.fieldId
          setTimeout (=> @classList.add 'dragging'), 0
        li.addEventListener 'dragend', ->
          @classList.remove 'dragging'
          ul.querySelectorAll('li').forEach (el) -> el.classList.remove 'drag-over'
        li.addEventListener 'dragover', (e) ->
          e.preventDefault()
          e.dataTransfer.dropEffect = 'move'
          ul.querySelectorAll('li').forEach (el) -> el.classList.remove 'drag-over'
          @classList.add 'drag-over' unless @ == dragSrc
        li.addEventListener 'drop', (e) ->
          e.preventDefault()
          target = e.currentTarget
          return if dragSrc == target
          rect = target.getBoundingClientRect()
          insertBefore = e.clientY < rect.top + rect.height / 2
          if insertBefore
            ul.insertBefore dragSrc, target
          else
            target.after dragSrc
          newOrder = Array.from(ul.querySelectorAll('li')).map (el) -> el.dataset.fieldId
          GQL.mutate(app._reorderFieldsMutation, { spaceId: app._currentSpace.id, fieldIds: newOrder })
            .then (res) ->
              app._currentSpace.fields = res.reorderFields
              app._syncSpaceFields app._currentSpace
              app.renderFieldsList()
              app._mountDataView app._currentSpace
            .catch (err) -> tdbAlert app._err(err), 'error'
        ul.appendChild li

  handleFieldSubmit: (app) ->
    return unless app._currentSpace
    name    = app.el.fieldName().value.trim()
    type    = app.el.fieldType().value
    notNull = app.el.fieldNotNull().checked
    unless name
      app.el.fieldName().classList.add 'input-error'
      app.el.fieldName().placeholder = app._t('ui.validation.groupNameRequired')
      app.el.fieldName().focus()
      return
    app.el.fieldName().classList.remove 'input-error'
    app.el.fieldName().placeholder = app._t('ui.fields.namePlaceholder')

    if app._editingFieldId
      originalField = (app._currentSpace?.fields or []).find (f) -> f.id == app._editingFieldId
      originalType = originalField?.fieldType
      formulaType = document.querySelector('input[name="formula-type"]:checked').value
      opts = { name, notNull }

      if type != originalType
        conversionFormula = null
        conversionLang = 'lua'
        if formulaType != 'none'
          conversionFormula = app.el.fieldFormula().value.trim() or null
          conversionLang = app.el.formulaLanguage()?.value or 'lua'

        Spaces.changeFieldType(app._editingFieldId, type, conversionFormula, conversionLang)
          .then ->
            if type == 'Relation'
              toSpaceId   = app.el.relToSpace().value
              reprFormula = app.el.relReprFormula().value.trim()
              return unless toSpaceId
              Spaces.getWithFields(toSpaceId).then (targetSpace) ->
                idField = (targetSpace.fields or []).find (f) -> f.fieldType == 'Sequence'
                unless idField
                  tdbAlert app._t('ui.alerts.targetNoSequence'), 'warn'
                  return

                Spaces.createRelation(
                  "#{app._currentSpace.name}_#{app.el.fieldName().value}_rel"
                  app._currentSpace.id
                  app._editingFieldId
                  toSpaceId
                  idField.id
                  reprFormula
                )
            else
              app.updateFieldProperties(app._editingFieldId, opts, formulaType)
          .catch (err) -> tdbAlert app._err(err), 'error'
      else
        app.updateFieldProperties(app._editingFieldId, opts, formulaType)

    else if type == 'Relation'
      toSpaceId   = app.el.relToSpace().value
      reprFormula = app.el.relReprFormula().value.trim()
      return unless toSpaceId
      Spaces.getWithFields(toSpaceId).then (targetSpace) ->
        idField = (targetSpace.fields or []).find (f) -> f.fieldType == 'Sequence'
        unless idField
          tdbAlert app._t('ui.alerts.targetNoSequence'), 'warn'
          return
        Spaces.addField(app._currentSpace.id, name, 'Int', notNull, '')
          .then (newField) ->
            Spaces.createRelation(name, app._currentSpace.id, newField.id, toSpaceId, idField.id, reprFormula)
              .then ->
                Spaces.getWithFields(app._currentSpace.id).then (full) ->
                  app._currentSpace = full
                  app._syncSpaceFields full
                  app.renderFieldsList()
                  app._mountDataView full
              .catch (err) -> tdbAlert app._err(err), 'error'
          .catch (err) -> tdbAlert app._err(err), 'error'
      app._resetFieldForm()

    else
      formulaType   = document.querySelector('input[name="formula-type"]:checked').value
      formulaOpts = window.AppFieldsHelpers.applyFormulaOptions app, {}, formulaType, null
      reprFormula = app.el.fieldReprFormula()?.value.trim() or null
      Spaces.addField(
        app._currentSpace.id
        name
        type
        notNull
        ''
        formulaOpts.formula
        formulaOpts.triggerFields
        formulaOpts.language
        reprFormula
      )
        .then ->
          Spaces.getWithFields(app._currentSpace.id).then (full) ->
            app._currentSpace = full
            app._syncSpaceFields full
            app.renderFieldsList()
            app._mountDataView full
        .catch (err) -> tdbAlert app._err(err), 'error'
      app._resetFieldForm()
