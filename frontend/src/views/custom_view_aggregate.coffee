# custom_view_aggregate.coffee — aggregate widget rendering extracted from custom_view.coffee
# Extends the CustomView class (defined in custom_view.js) via its prototype.
# Loaded after views/custom_view.js.

Object.assign window.CustomView::,
  # Render an aggregate (GROUP BY) widget as a read-only table.
  _renderAggregate: (container, wNode) ->
    groupBy   = wNode.groupBy   or []
    aggregate = wNode.aggregate or []
    spaceName = wNode.space
    unless spaceName
      container.innerHTML = "<p style='color:#aaa;padding:.5rem'>Paramètre <code>space</code> manquant.</p>"
      return

    # Show loading state
    container.innerHTML = "<p style='color:#888;padding:.5rem'>Chargement…</p>"

    # Normalize aggregate: ensure each entry has fn and as
    makeAlias = (agg) ->
      return agg.as if agg.as
      if not agg.field then 'count' else "#{agg.fn}_#{agg.field}"

    aggInput = for agg in aggregate
      fn: agg.fn, field: (agg.field or null), as: makeAlias(agg)

    Spaces.aggregateSpace(spaceName, groupBy, aggInput).then (rows) =>
      container.innerHTML = ''
      unless rows and rows.length > 0
        container.innerHTML = "<p style='color:#aaa;padding:.5rem'>Aucun résultat.</p>"
        return

      # Evaluate computed columns (client-side JS expressions on each row)
      computed = wNode.computed or []
      computedFns = []
      formulaErrors = []
      for col in computed
        do (col) ->
          try
            fn = new Function('row', "try { return (#{col.expr}); } catch(e) { return '⚠ ' + e.message; }")
            computedFns.push { as: col.as, fn }
          catch e
            formulaErrors.push "#{col.as}: #{e.message}"
            computedFns.push { as: col.as, fn: -> "⚠ formule invalide" }
      if formulaErrors.length > 0
        errDiv = document.createElement 'p'
        errDiv.style.cssText = 'color:#c55;padding:.3rem .5rem;font-size:.85rem;margin:0'
        errDiv.textContent = "Formule invalide : #{formulaErrors.join('; ')}"
        container.appendChild errDiv

      # Augment rows with computed values
      if computedFns.length > 0
        for row in rows
          for c in computedFns
            row[c.as] = c.fn row

      # Build column list from first row keys (preserve groupBy order first)
      keys = groupBy.slice()
      for agg in aggInput
        keys.push agg.as unless agg.as in keys
      for col in computed
        keys.push col.as unless col.as in keys

      tbl = document.createElement 'table'
      tbl.className = 'agg-table'

      thead = document.createElement 'thead'
      tr = document.createElement 'tr'
      for k in keys
        th = document.createElement 'th'
        th.textContent = k
        tr.appendChild th
      thead.appendChild tr
      tbl.appendChild thead

      tbody = document.createElement 'tbody'
      for row in rows
        tr = document.createElement 'tr'
        for k in keys
          td = document.createElement 'td'
          v = row[k]
          td.textContent = if v? then String(v) else ''
          tr.appendChild td
        tbody.appendChild tr
      tbl.appendChild tbody
      container.appendChild tbl
    .catch (err) =>
      @_setMessage container, "Erreur : #{err.message or err}", 'color:#c55;padding:.5rem'
