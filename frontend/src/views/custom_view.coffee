# custom_view.coffee
# YAML-driven layout renderer.
#
# YAML format example:
#
#   layout:
#     direction: vertical
#     children:
#       - direction: horizontal
#         children:
#           - widget:
#               id: liste-chorales          # identifiant unique du widget (obligatoire si référencé)
#               title: Chorales
#               space: chorale
#           - widget:
#               title: Choristes
#               space: choristes
#               depends_on:
#                 widget: liste-chorales    # id du widget source
#                 field: chorale_id         # FK field in this space
#                 from_field: id            # referenced field in the source widget's space

window.CustomView = class CustomView
  constructor: (@container, @yamlText, @allSpaces) ->
    @_widgets   = []   # list of { dataView, node, el }
    @_widgetsById = {} # id -> entry

  mount: ->
    @container.innerHTML = ''
    @_widgets     = []
    @_widgetsById = {}
    try
      parsed = jsyaml.load @yamlText
    catch e
      @container.innerHTML = "<p style='color:red;padding:1rem'>YAML invalide : #{e.message}</p>"
      return

    root = parsed?.layout
    unless root
      @container.innerHTML = "<p style='color:#888;padding:1rem'>Pas de section <code>layout</code> dans le YAML.</p>"
      return

    el = @_renderZoneOrWidget root
    el.style.flex = '1'
    @container.style.cssText = 'display:flex;flex-direction:column;height:100%;'
    @container.appendChild el

    # Wire depends_on after all widgets are mounted
    @_wireDepends()

    # Refresh grid layouts now that elements are in the live DOM
    setTimeout =>
      for entry in @_widgets
        entry.dataView?._grid?.refreshLayout()
    , 0

  _renderZoneOrWidget: (node) ->
    if node.widget
      return @_renderWidget node.widget
    # Zone node (direction + children)
    zone = document.createElement 'div'
    zone.className = "cv-zone #{node.direction or 'vertical'}"
    for child in (node.children or [])
      zone.appendChild @_renderZoneOrWidget child
    zone

  _renderWidget: (wNode) ->
    sp = @_findSpace wNode.space
    wrapper = document.createElement 'div'
    wrapper.className = 'cv-widget'

    # Title bar with optional delete button
    titleBar = document.createElement 'div'
    titleBar.className = 'cv-widget-title'
    titleText = document.createElement 'span'
    titleText.textContent = wNode.title or wNode.space or ''
    titleBar.appendChild titleText
    delBtn = document.createElement 'button'
    delBtn.className = 'cv-widget-delete-btn'
    delBtn.title = 'Supprimer les enregistrements sélectionnés'
    delBtn.textContent = '🗑'
    titleBar.appendChild delBtn
    wrapper.appendChild titleBar

    body = document.createElement 'div'
    body.className = 'cv-widget-body'
    wrapper.appendChild body

    unless sp
      body.innerHTML = "<p style='color:#aaa;padding:.5rem'>Espace « #{wNode.space} » introuvable.</p>"
      entry = { dataView: null, node: wNode, el: wrapper }
      @_widgets.push entry
      @_widgetsById[wNode.id] = entry if wNode.id
      return wrapper

    dv = new DataView body, sp
    dv.mount()
    delBtn.addEventListener 'click', => dv.deleteSelected()
    entry = { dataView: dv, node: wNode, el: wrapper }
    @_widgets.push entry
    @_widgetsById[wNode.id] = entry if wNode.id
    wrapper

  _wireDepends: ->
    for entry in @_widgets
      dep = entry.node.depends_on
      continue unless dep
      src = @_widgetsById[dep.widget]
      unless src?.dataView
        console.warn "depends_on: widget id '#{dep.widget}' introuvable ou sans dataView"
        continue

      # When a row is clicked in the source grid, filter this widget and set FK default
      do (entry, dep, src) =>
        src.dataView._grid?.on 'click', (ev) =>
          rowKey = ev.rowKey
          return unless rowKey?
          rowData = src.dataView._currentData[rowKey]
          return unless rowData and not rowData.__isNew
          filterVal = String(rowData[dep.from_field or 'id'])
          defaults = {}
          defaults[dep.field] = filterVal
          entry.dataView?.setDefaultValues defaults
          entry.dataView?.setFilter { field: dep.field, value: filterVal }

  _findSpace: (nameOrId) ->
    return null unless nameOrId
    @allSpaces.find (sp) -> sp.name == nameOrId or sp.id == nameOrId

  unmount: ->
    for entry in @_widgets
      entry.dataView?.unmount?()
    @container.innerHTML = ''
    @_widgets     = []
    @_widgetsById = {}
