# app.coffee — main application bootstrap and UI orchestration.

REMOVE_FIELD = """
  mutation RemoveField($fieldId: ID!) { removeField(fieldId: $fieldId) }
"""

REORDER_FIELDS = """
  mutation ReorderFields($spaceId: ID!, $fieldIds: [ID!]!) {
    reorderFields(spaceId: $spaceId, fieldIds: $fieldIds) { id name fieldType notNull position }
  }
"""

LIST_CUSTOM_VIEWS = """
  query { customViews { id name description yaml } }
"""

CREATE_CUSTOM_VIEW = """
  mutation CreateCustomView($input: CreateCustomViewInput!) {
    createCustomView(input: $input) { id name yaml }
  }
"""

UPDATE_CUSTOM_VIEW = """
  mutation UpdateCustomView($id: ID!, $input: UpdateCustomViewInput!) {
    updateCustomView(id: $id, input: $input) { id name yaml }
  }
"""

DELETE_CUSTOM_VIEW = """
  mutation DeleteCustomView($id: ID!) { deleteCustomView(id: $id) }
"""

window.App =
  _currentSpace:     null
  _currentCustomView: null
  _activeDataView:   null
  _activeCustomView: null
  _allSpaces:        []
  _editingFieldId:   null   # fieldId being edited in the Champs form, or null

  # ── DOM refs ────────────────────────────────────────────────────────────────
  el:
    loginOverlay:      -> document.getElementById 'login-overlay'
    main:              -> document.getElementById 'main'
    loginUser:         -> document.getElementById 'login-username'
    loginPass:         -> document.getElementById 'login-password'
    loginBtn:          -> document.getElementById 'login-btn'
    loginError:        -> document.getElementById 'login-error'
    currentUser:       -> document.getElementById 'current-user'
    logoutBtn:         -> document.getElementById 'logout-btn'
    spaceList:         -> document.getElementById 'space-list'
    newSpaceBtn:       -> document.getElementById 'new-space-btn'
    customViewList:    -> document.getElementById 'custom-view-list'
    newViewBtn:        -> document.getElementById 'new-view-btn'
    dataToolbar:       -> document.getElementById 'data-toolbar'
    dataTitle:         -> document.getElementById 'data-title'
    renameSpaceBtn:    -> document.getElementById 'rename-space-btn'
    deleteSpaceBtn:    -> document.getElementById 'delete-space-btn'
    fieldsBtn:         -> document.getElementById 'fields-btn'
    deleteRowsBtn:     -> document.getElementById 'delete-rows-btn'
    gridContainer:     -> document.getElementById 'grid-container'
    customViewContainer: -> document.getElementById 'custom-view-container'
    fieldsPanel:       -> document.getElementById 'fields-panel'
    fieldsPanelClose:  -> document.getElementById 'fields-panel-close'
    fieldsList:        -> document.getElementById 'fields-list'
    fieldName:         -> document.getElementById 'field-name'
    fieldType:         -> document.getElementById 'field-type'
    fieldNotNull:      -> document.getElementById 'field-notnull'
    fieldFormula:      -> document.getElementById 'field-formula'
    formulaLanguage:   -> document.getElementById 'formula-language'
    fieldTriggerFields: -> document.getElementById 'field-trigger-fields'
    formulaBody:       -> document.getElementById 'formula-body'
    triggerFieldsRow:  -> document.getElementById 'trigger-fields-row'
    fieldAddBtn:       -> document.getElementById 'field-add-btn'
    fieldCancelBtn:    -> document.getElementById 'field-cancel-btn'
    relTargetRow:      -> document.getElementById 'rel-target-row'
    relToSpace:        -> document.getElementById 'rel-to-space'
    yamlEditorPanel:   -> document.getElementById 'yaml-editor-panel'
    yamlViewName:      -> document.getElementById 'yaml-view-name'
    yamlEditBtn:       -> document.getElementById 'yaml-edit-btn'
    yamlCloseEditorBtn: -> document.getElementById 'yaml-close-editor-btn'
    yamlEditor:        -> document.getElementById 'yaml-editor'
    yamlSaveBtn:       -> document.getElementById 'yaml-save-btn'
    yamlPreviewBtn:    -> document.getElementById 'yaml-preview-btn'
    yamlDeleteBtn:     -> document.getElementById 'yaml-delete-btn'
    welcome:           -> document.getElementById 'welcome'
    contentRow:        -> document.getElementById 'content-row'

  # ── Bootstrap ───────────────────────────────────────────────────────────────
  init: ->
    @_bindLogin()
    @_bindSidebar()
    @_bindDataToolbar()
    @_bindFieldsPanel()
    @_bindYamlEditor()

  # ── Login ───────────────────────────────────────────────────────────────────
  _bindLogin: ->
    doLogin = =>
      username = @el.loginUser().value.trim()
      password = @el.loginPass().value
      return unless username and password
      @el.loginError().textContent = ''
      Auth.login(username, password)
        .then (user) =>
          @showMain user
          @_loadAll()
        .catch (err) =>
          @el.loginError().textContent = err.message

    @el.loginBtn().addEventListener 'click', doLogin
    onEnter = (e) -> doLogin() if e.key == 'Enter'
    @el.loginUser().addEventListener 'keydown', onEnter
    @el.loginPass().addEventListener 'keydown', onEnter

  showLogin: ->
    @el.loginOverlay().classList.remove 'hidden'
    @el.main().classList.add 'hidden'

  showMain: (user) ->
    @el.loginOverlay().classList.add 'hidden'
    @el.main().classList.remove 'hidden'
    @el.currentUser().textContent = user.username

  # ── Sidebar ─────────────────────────────────────────────────────────────────
  _bindSidebar: ->
    @el.newSpaceBtn().addEventListener 'click', =>
      name = prompt 'Nom du nouvel espace :'
      return unless name?.trim()
      Spaces.create(name.trim())
        .then => @_loadAll()
        .catch (err) -> alert "Erreur : #{err.message}"

    @el.newViewBtn().addEventListener 'click', =>
      name = prompt 'Nom de la nouvelle vue :'
      return unless name?.trim()
      GQL.mutate(CREATE_CUSTOM_VIEW, { input: { name: name.trim(), yaml: "layout:\n  direction: vertical\n  children: []\n" } })
        .then (data) =>
          @loadCustomViews().then =>
            cv = data.createCustomView
            @selectCustomView cv
        .catch (err) -> alert "Erreur : #{err.message}"

    @el.logoutBtn().addEventListener 'click', =>
      Auth.logout()

  # ── Load everything ─────────────────────────────────────────────────────────
  _loadAll: ->
    Promise.all([@loadSpaces(), @loadCustomViews()]).then => @_restoreFromHash()

  # ── Hash-based navigation ────────────────────────────────────────────────────
  _restoreFromHash: ->
    hash = window.location.hash
    if m = hash.match /^#space\/(.+)$/
      spaceId = m[1]
      sp = (@_allSpaces or []).find (s) -> s.id == spaceId
      @selectSpace sp if sp
    else if m = hash.match /^#view\/(.+)$/
      viewId = m[1]
      ul = @el.customViewList()
      cvItems = ul.querySelectorAll 'li'
      for li in cvItems
        if li.dataset.id == viewId
          li.click()
          break

  # ── Spaces (Données section) ─────────────────────────────────────────────────
  loadSpaces: ->
    Spaces.list()
      .then (spaces) =>
        @_allSpaces = spaces
        @renderSpaceList spaces
      .catch (err) -> console.error 'loadSpaces', err

  renderSpaceList: (spaces) ->
    ul = @el.spaceList()
    ul.innerHTML = ''
    for sp in spaces
      li = document.createElement 'li'
      li.textContent = sp.name
      li.dataset.id  = sp.id
      do (sp) =>
        li.addEventListener 'click', => @selectSpace sp
      ul.appendChild li

  selectSpace: (sp) ->
    history.replaceState null, '', "#space/#{sp.id}"
    for li in @el.customViewList().querySelectorAll 'li'
      li.classList.remove 'active'
    # Highlight space item
    for li in @el.spaceList().querySelectorAll 'li'
      li.classList.toggle 'active', li.dataset.id == sp.id

    @_currentCustomView = null
    @_activeCustomView?.unmount?()
    @_activeCustomView = null

    # Close fields panel
    @el.fieldsPanel().classList.add 'hidden'
    @el.fieldsBtn().classList.remove 'active'

    # Show data toolbar, hide YAML panel + custom view
    @el.dataToolbar().classList.remove 'hidden'
    @el.yamlEditorPanel().classList.add 'hidden'
    @el.customViewContainer().classList.add 'hidden'
    @el.gridContainer().classList.remove 'hidden'
    @el.welcome().classList.add 'hidden'
    @el.contentRow().classList.remove 'hidden'

    Spaces.getWithFields(sp.id)
      .then (full) =>
        @_currentSpace = full
        @el.dataTitle().textContent = full.name
        @_mountDataView full
      .catch (err) -> console.error 'selectSpace', err

  # Keep @_allSpaces in sync after any field mutation on the current space.
  # If a custom view is active, rebuilds it so widgets get the fresh columns.
  _syncSpaceFields: (space) ->
    @_allSpaces = (@_allSpaces or []).map (s) => if s.id == space.id then space else s
    if @_activeCustomView and @_currentCustomView?.yaml?.trim()
      @_renderCustomViewPreview @_currentCustomView.yaml

  _mountDataView: (space) ->
    @_activeDataView?.unmount?()
    container = @el.gridContainer()
    @_activeDataView = new DataView container, space
    @_activeDataView.mount()

  # ── Custom views (Vues section) ──────────────────────────────────────────────
  loadCustomViews: ->
    GQL.query(LIST_CUSTOM_VIEWS)
      .then (data) => @renderCustomViewList data.customViews
      .catch (err) -> console.error 'loadCustomViews', err

  renderCustomViewList: (views) ->
    ul = @el.customViewList()
    ul.innerHTML = ''
    for cv in (views or [])
      li = document.createElement 'li'
      li.textContent = cv.name
      li.dataset.id  = cv.id
      do (cv) =>
        li.addEventListener 'click', => @selectCustomView cv
      ul.appendChild li

  selectCustomView: (cv) ->
    history.replaceState null, '', "#view/#{cv.id}"
    @_currentCustomView = cv
    # Deactivate space items
    for li in @el.spaceList().querySelectorAll 'li'
      li.classList.remove 'active'
    for li in @el.customViewList().querySelectorAll 'li'
      li.classList.toggle 'active', li.dataset.id == cv.id

    @_currentSpace = null
    @_activeDataView?.unmount?()
    @_activeDataView = null

    # Hide data grid area
    @el.dataToolbar().classList.add 'hidden'
    @el.fieldsPanel().classList.add 'hidden'
    @el.gridContainer().classList.add 'hidden'
    @el.welcome().classList.add 'hidden'
    @el.contentRow().classList.remove 'hidden'

    panel = @el.yamlEditorPanel()
    panel.classList.remove 'hidden'
    @el.yamlViewName().textContent = cv.name
    @el.yamlEditor().value = cv.yaml or ''

    # If YAML exists, start in view mode; otherwise go straight to editor
    if cv.yaml?.trim()
      @_setYamlMode 'view'
      @_renderCustomViewPreview cv.yaml
    else
      @_setYamlMode 'edit'
      @el.customViewContainer().classList.add 'hidden'

  _setYamlMode: (mode) ->   # 'view' or 'edit'
    panel = @el.yamlEditorPanel()
    panel.classList.toggle 'view-mode', mode == 'view'
    panel.classList.toggle 'edit-mode', mode == 'edit'

  _renderCustomViewPreview: (yamlText) ->
    container = @el.customViewContainer()
    @_activeCustomView?.unmount?()
    container.innerHTML = ''
    container.classList.remove 'hidden'
    @_activeCustomView = new CustomView container, yamlText, @_allSpaces
    @_activeCustomView.mount()

  # ── YAML editor ─────────────────────────────────────────────────────────────
  _bindYamlEditor: ->
    @el.yamlEditBtn().addEventListener 'click', =>
      @_setYamlMode 'edit'

    @el.yamlCloseEditorBtn().addEventListener 'click', =>
      @_setYamlMode 'view'

    @el.yamlSaveBtn().addEventListener 'click', =>
      cv = @_currentCustomView
      return unless cv
      yaml = @el.yamlEditor().value
      GQL.mutate(UPDATE_CUSTOM_VIEW, { id: cv.id, input: { yaml } })
        .then (data) =>
          @_currentCustomView = data.updateCustomView
          @_renderCustomViewPreview yaml
          @_setYamlMode 'view'
          @loadCustomViews()
        .catch (err) -> alert "Erreur : #{err.message}"

    @el.yamlPreviewBtn().addEventListener 'click', =>
      return unless @_currentCustomView
      @_renderCustomViewPreview @el.yamlEditor().value

    @el.yamlDeleteBtn().addEventListener 'click', =>
      cv = @_currentCustomView
      return unless cv
      return unless confirm "Supprimer la vue « #{cv.name} » ?"
      GQL.mutate(DELETE_CUSTOM_VIEW, { id: cv.id })
        .then =>
          @_currentCustomView = null
          @_activeCustomView?.unmount?()
          @_activeCustomView = null
          @el.yamlEditorPanel().classList.add 'hidden'
          @el.customViewContainer().classList.add 'hidden'
          @el.welcome().classList.remove 'hidden'
          @loadCustomViews()
        .catch (err) -> alert "Erreur : #{err.message}"

  # ── Data toolbar ─────────────────────────────────────────────────────────────
  _bindDataToolbar: ->
    @el.deleteRowsBtn().addEventListener 'click', =>
      @_activeDataView?.deleteSelected()

    @el.deleteSpaceBtn().addEventListener 'click', =>
      return unless @_currentSpace
      name = @_currentSpace.name
      return unless confirm "Supprimer l'espace « #{name} » et toutes ses données ?"
      Spaces.delete(@_currentSpace.id)
        .then =>
          @_currentSpace = null
          @_activeDataView?.unmount?()
          @_activeDataView = null
          @el.dataToolbar().classList.add 'hidden'
          @el.fieldsPanel().classList.add 'hidden'
          @el.fieldsBtn().classList.remove 'active'
          @el.welcome().classList.remove 'hidden'
          @_loadAll()
        .catch (err) -> alert "Erreur : #{err.message}"

    @el.renameSpaceBtn().addEventListener 'click', =>
      return unless @_currentSpace
      newName = prompt "Nouveau nom de l'espace :", @_currentSpace.name
      return unless newName?.trim() and newName.trim() != @_currentSpace.name
      Spaces.update(@_currentSpace.id, newName.trim())
        .then (updated) =>
          @_currentSpace.name = updated.name
          @el.dataTitle().textContent = updated.name
          # Update sidebar
          li = @el.spaceList().querySelector("li[data-id='#{updated.id}']")
          li.textContent = updated.name if li
        .catch (err) -> alert "Erreur : #{err.message}"

  # ── Fields panel ─────────────────────────────────────────────────────────────
  _bindFieldsPanel: ->
    @el.fieldsBtn().addEventListener 'click', =>
      panel = @el.fieldsPanel()
      btn   = @el.fieldsBtn()
      if panel.classList.contains 'hidden'
        panel.classList.remove 'hidden'
        btn.classList.add 'active'
        @renderFieldsList()
      else
        panel.classList.add 'hidden'
        btn.classList.remove 'active'

    @el.fieldsPanelClose().addEventListener 'click', =>
      @el.fieldsPanel().classList.add 'hidden'
      @el.fieldsBtn().classList.remove 'active'

    # Show/hide formula section and relation target based on type selection
    @el.fieldType().addEventListener 'change', =>
      @_onFieldTypeChange()

    # Show/hide formula textarea and trigger-fields row based on radio selection
    document.querySelectorAll('input[name="formula-type"]').forEach (radio) =>
      radio.addEventListener 'change', =>
        val = document.querySelector('input[name="formula-type"]:checked').value
        @el.formulaBody().classList.toggle 'hidden', val == 'none'
        @el.triggerFieldsRow().classList.toggle 'hidden', val != 'trigger'

    @el.fieldCancelBtn().addEventListener 'click', =>
      @_resetFieldForm()

    @el.fieldAddBtn().addEventListener 'click', =>
      return unless @_currentSpace
      name    = @el.fieldName().value.trim()
      type    = @el.fieldType().value
      notNull = @el.fieldNotNull().checked
      return unless name

      if @_editingFieldId
        # ── Update existing field ──────────────────────────────────────────
        formulaType = document.querySelector('input[name="formula-type"]:checked').value
        opts = { name, notNull }
        if formulaType != 'none'
          opts.formula  = @el.fieldFormula().value.trim() or null
          opts.language = @el.formulaLanguage()?.value or 'lua'
          if formulaType == 'trigger' and opts.formula
            raw = @el.fieldTriggerFields().value.trim()
            if raw == '*'
              opts.triggerFields = ['*']
            else if raw == ''
              opts.triggerFields = []
            else
              opts.triggerFields = (s.trim() for s in raw.split(',') when s.trim())
        else
          opts.formula       = ''
          opts.triggerFields = null
          opts.language      = 'lua'
        Spaces.updateField(@_editingFieldId, opts)
          .then =>
            Spaces.getWithFields(@_currentSpace.id).then (full) =>
              @_currentSpace = full
              @_syncSpaceFields full
              @renderFieldsList()
              @_mountDataView full
          .catch (err) -> alert "Erreur : #{err.message}"
        @_resetFieldForm()

      else if type == 'Relation'
        # ── Create relation field ──────────────────────────────────────────
        toSpaceId = @el.relToSpace().value
        return unless toSpaceId
        Spaces.getWithFields(toSpaceId).then (targetSpace) =>
          idField = (targetSpace.fields or []).find (f) -> f.fieldType == 'Sequence'
          return alert "L'espace cible n'a pas de champ Séquence." unless idField
          Spaces.addField(@_currentSpace.id, name, 'Int', notNull, '')
            .then (newField) =>
              Spaces.createRelation(name, @_currentSpace.id, newField.id, toSpaceId, idField.id)
                .then =>
                  Spaces.getWithFields(@_currentSpace.id).then (full) =>
                    @_currentSpace = full
                    @_syncSpaceFields full
                    @renderFieldsList()
                    @_mountDataView full
                .catch (err) -> alert "Erreur : #{err.message}"
            .catch (err) -> alert "Erreur : #{err.message}"
        @_resetFieldForm()

      else
        # ── Add new regular field ──────────────────────────────────────────
        formulaType   = document.querySelector('input[name="formula-type"]:checked').value
        formula       = null
        triggerFields = null
        language      = @el.formulaLanguage()?.value or 'lua'
        if formulaType != 'none'
          formula = @el.fieldFormula().value.trim() or null
          if formulaType == 'trigger' and formula
            raw = @el.fieldTriggerFields().value.trim()
            if raw == '*'
              triggerFields = ['*']
            else if raw == ''
              triggerFields = []
            else
              triggerFields = (s.trim() for s in raw.split(',') when s.trim())
        Spaces.addField(@_currentSpace.id, name, type, notNull, '', formula, triggerFields, language)
          .then =>
            Spaces.getWithFields(@_currentSpace.id).then (full) =>
              @_currentSpace = full
              @_syncSpaceFields full
              @renderFieldsList()
              @_mountDataView full
          .catch (err) -> alert "Erreur : #{err.message}"
        @_resetFieldForm()

  _onFieldTypeChange: ->
    type = @el.fieldType().value
    isRelation = type == 'Relation'
    @el.relTargetRow().classList.toggle 'hidden', !isRelation
    @el.fieldNotNull().closest('label')?.classList.toggle 'hidden', isRelation
    formulaSection = @el.formulaBody().closest('.formula-section')
    formulaSection?.classList.toggle 'hidden', isRelation
    if isRelation
      # Populate target space selector
      sel = @el.relToSpace()
      sel.innerHTML = '<option value="">Cible…</option>'
      for sp in (@_allSpaces or [])
        opt = document.createElement 'option'
        opt.value = sp.id
        opt.textContent = sp.name
        sel.appendChild opt

  _resetFieldForm: ->
    @_editingFieldId = null
    @el.fieldName().value = ''
    @el.fieldType().value = 'String'
    @el.fieldNotNull().checked = false
    @el.fieldFormula().value = ''
    @el.fieldTriggerFields().value = ''
    if @el.formulaLanguage() then @el.formulaLanguage().value = 'lua'
    document.querySelector('input[name="formula-type"][value="none"]').checked = true
    @el.formulaBody().classList.add 'hidden'
    @el.triggerFieldsRow().classList.add 'hidden'
    @el.relTargetRow().classList.add 'hidden'
    @el.fieldNotNull().closest('label')?.classList.remove 'hidden'
    formulaSection = @el.formulaBody().closest('.formula-section')
    formulaSection?.classList.remove 'hidden'
    @el.fieldAddBtn().textContent = 'Ajouter'
    @el.fieldCancelBtn().classList.add 'hidden'

  renderFieldsList: ->
    return unless @_currentSpace
    ul = @el.fieldsList()
    ul.innerHTML = ''
    fields = @_currentSpace.fields or []
    # Fetch relations and render everything in one shot
    Spaces.listRelations(@_currentSpace.id).then (relations) =>
      # Build a map: fromFieldId → relation (with target space name resolved)
      relMap = {}
      for r in (relations or [])
        relMap[r.fromFieldId] = r
      # Resolve target space names from _allSpaces
      spaceMap = {}
      for sp in (@_allSpaces or [])
        spaceMap[sp.id] = sp.name

      if fields.length == 0
        li = document.createElement 'li'
        li.textContent = 'Aucun champ défini.'
        li.style.color = '#aaa'
        ul.appendChild li
        return

      dragSrc = null
      for f in fields
        li = document.createElement 'li'
        li.draggable = true
        li.dataset.fieldId = f.id
        li.style.cursor = 'grab'

        handle = document.createElement 'span'
        handle.textContent = '⠿'
        handle.title = 'Glisser pour réordonner'
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
              if f.triggerFields.length == 0 then 'création'
              else if f.triggerFields[0] == '*' then 'tout changement'
              else f.triggerFields.join(', ')
            fb.textContent = '⚡'
            fb.title = "Trigger formula#{langLabel} (#{triggerDesc}) : #{f.formula}"
          else
            fb.className = 'field-formula-badge'
            fb.textContent = 'λ'
            fb.title = "Colonne calculée#{langLabel} : #{f.formula}"
          name.appendChild fb

        # Edit button (not for Sequence fields)
        editBtn = document.createElement 'button'
        editBtn.textContent = '✎'
        editBtn.title = 'Modifier ce champ'
        editBtn.style.cssText = 'background:none;border:none;cursor:pointer;color:#888;font-size:.9rem;margin-left:.2rem;'
        do (field = f, relation = rel) =>
          editBtn.addEventListener 'click', =>
            @_editingFieldId = field.id
            @el.fieldAddBtn().textContent = 'Mettre à jour'
            @el.fieldCancelBtn().classList.remove 'hidden'
            @el.fieldName().value = field.name
            if relation
              # Editing a relation field: show only Cible
              @el.fieldType().value = 'Relation'
              @_onFieldTypeChange()
              @el.relToSpace().value = relation.toSpaceId
            else
              @el.fieldType().value = field.fieldType
              @_onFieldTypeChange()
              @el.fieldNotNull().checked = field.notNull
              if field.formula and field.formula != ''
                if field.triggerFields
                  document.querySelector('input[name="formula-type"][value="trigger"]').checked = true
                  @el.triggerFieldsRow().classList.remove 'hidden'
                  tf = field.triggerFields
                  @el.fieldTriggerFields().value =
                    if tf.length == 0 then ''
                    else if tf[0] == '*' then '*'
                    else tf.join(', ')
                else
                  document.querySelector('input[name="formula-type"][value="formula"]').checked = true
                @el.formulaBody().classList.remove 'hidden'
                @el.fieldFormula().value = field.formula
                if @el.formulaLanguage() then @el.formulaLanguage().value = field.language or 'lua'
              else
                document.querySelector('input[name="formula-type"][value="none"]').checked = true
                @el.formulaBody().classList.add 'hidden'
            @el.fieldName().focus()

        del = document.createElement 'button'
        del.textContent = '✕'
        del.title = 'Supprimer ce champ'
        del.style.cssText = 'margin-left:.2rem;background:none;border:none;cursor:pointer;color:#aaa;font-size:.9rem;'
        do (fieldId = f.id, fieldName = f.name, relation = rel) =>
          del.addEventListener 'click', =>
            return unless confirm "Supprimer le champ « #{fieldName} » ?"
            doDelete = =>
              GQL.mutate(REMOVE_FIELD, { fieldId })
                .then =>
                  Spaces.getWithFields(@_currentSpace.id).then (full) =>
                    @_currentSpace = full
                    @_syncSpaceFields full
                    @renderFieldsList()
                    @_mountDataView full
                .catch (err) -> alert "Erreur : #{err.message}"
            if relation
              Spaces.deleteRelation(relation.id).then(doDelete).catch (err) -> alert "Erreur : #{err.message}"
            else
              doDelete()

        li.appendChild handle
        li.appendChild badge
        li.appendChild name
        li.appendChild editBtn
        li.appendChild del

        # Drag events
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
        li.addEventListener 'drop', (e) =>
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
          GQL.mutate(REORDER_FIELDS, { spaceId: @_currentSpace.id, fieldIds: newOrder })
            .then (res) =>
              @_currentSpace.fields = res.reorderFields
              @_syncSpaceFields @_currentSpace
              @renderFieldsList()
              @_mountDataView @_currentSpace
            .catch (err) -> console.error 'reorderFields', err
        ul.appendChild li

# ── Entry point ────────────────────────────────────────────────────────────────
document.addEventListener 'DOMContentLoaded', ->
  GQL.loadToken()
  App.init()
  Auth.restoreSession()
    .then (user) ->
      if user
        App.showMain user
        App._loadAll()
    .catch ->
      GQL.clearToken()
