local R = require('tests.runner')
local wid = require('core.widget_ids')
local yaml = require('yaml')
local YAML_NO_ID = [[layout:
  direction: vertical
  children:
    - widget:
        title: Test
        space: test
]]
local YAML_WITH_ID = [[layout:
  direction: vertical
  children:
    - widget:
        id: kept_widget
        title: Test
        space: test
]]
local YAML_EMPTY_ID = [[layout:
  direction: vertical
  children:
    - widget:
        id: ''
        title: Test
        space: test
]]
local YAML_TWO_WIDGETS = [[layout:
  direction: horizontal
  children:
    - widget:
        title: A
        space: test
    - factor: 1
      widget:
        title: B
        space: test
]]
local YAML_NESTED_ZONES = [[layout:
  direction: horizontal
  children:
    - zone:
        id: zone_a
        factor: 1
        direction: vertical
        children:
          - widget:
              title: A
              space: test
    - zone:
        id: zone_b
        factor: 1
        direction: vertical
        children:
          - widget:
              title: B
              space: test
]]
local YAML_WITH_COMMENT = [[layout:
  direction: vertical
  # commentaire conserve
  children:
    - widget:
        title: Test
        space: test
]]
local ids_of
ids_of = function(text)
  local config = yaml.decode(text)
  local ids = { }
  local _list_0 = wid.collect_widgets(config)
  for _index_0 = 1, #_list_0 do
    local widget = _list_0[_index_0]
    table.insert(ids, tostring(widget.id))
  end
  return ids
end
return R.describe("WidgetIds — normalisation du texte YAML", function()
  R.it("attribue w_ + 8 hexadécimaux à un widget sans id", function()
    local new_yaml, changed = wid.ensure_widget_ids(YAML_NO_ID)
    R.ok(changed, 'changed')
    R.ne(new_yaml, YAML_NO_ID, 'texte modifié')
    local ids = ids_of(new_yaml)
    R.eq(#ids, 1)
    R.matches(ids[1], '^w_%x%x%x%x%x%x%x%x$')
    return R.ok(new_yaml:find('id: ' .. ids[1], 1, true), 'id écrit dans le texte')
  end)
  R.it("conserve un id existant", function()
    local new_yaml, changed = wid.ensure_widget_ids(YAML_WITH_ID)
    R.nok(changed, 'changed')
    R.eq(new_yaml, YAML_WITH_ID)
    return R.eq((ids_of(new_yaml))[1], 'kept_widget')
  end)
  R.it("remplit un id vide sans dupliquer la clé", function()
    local new_yaml, changed = wid.ensure_widget_ids(YAML_EMPTY_ID)
    R.ok(changed, 'changed')
    local ids = ids_of(new_yaml)
    R.eq(#ids, 1)
    R.matches(ids[1], '^w_%x%x%x%x%x%x%x%x$')
    local line_count = 0
    local _list_0
    do
      local _accum_0 = { }
      local _len_0 = 1
      for l in new_yaml:gmatch('[^\n]+') do
        if l:match('^%s*id%s*:') then
          _accum_0[_len_0] = l
          _len_0 = _len_0 + 1
        end
      end
      _list_0 = _accum_0
    end
    for _index_0 = 1, #_list_0 do
      local line = _list_0[_index_0]
      line_count = line_count + 1
    end
    return R.eq(line_count, 1, 'une seule ligne id')
  end)
  R.it("attribue des ids distincts à deux widgets", function()
    local new_yaml, changed = wid.ensure_widget_ids(YAML_TWO_WIDGETS)
    R.ok(changed, 'changed')
    local ids = ids_of(new_yaml)
    R.eq(#ids, 2)
    R.matches(ids[1], '^w_%x%x%x%x%x%x%x%x$')
    R.matches(ids[2], '^w_%x%x%x%x%x%x%x%x$')
    return R.ne(ids[1], ids[2], 'ids distincts')
  end)
  R.it("couvre les widgets des zones imbriquées", function()
    local new_yaml, changed = wid.ensure_widget_ids(YAML_NESTED_ZONES)
    R.ok(changed, 'changed')
    local ids = ids_of(new_yaml)
    R.eq(#ids, 2)
    R.matches(ids[1], '^w_%x%x%x%x%x%x%x%x$')
    R.matches(ids[2], '^w_%x%x%x%x%x%x%x%x$')
    return R.ne(ids[1], ids[2], 'ids distincts')
  end)
  R.it("préserve les commentaires écrits à la main", function()
    local new_yaml, changed = wid.ensure_widget_ids(YAML_WITH_COMMENT)
    R.ok(changed, 'changed')
    R.ok(new_yaml:find('# commentaire conserve', 1, true), 'commentaire conservé')
    return R.eq(#ids_of(new_yaml), 1)
  end)
  R.it("renvoie tel quel un YAML invalide", function()
    local invalid = "layout: [unclosed\n  bad"
    local new_yaml, changed = wid.ensure_widget_ids(invalid)
    R.nok(changed, 'changed')
    return R.eq(new_yaml, invalid)
  end)
  R.it("renvoie tel quel un YAML vide ou sans layout", function()
    local new_yaml, changed = wid.ensure_widget_ids('')
    R.nok(changed)
    R.eq(new_yaml, '')
    local no_layout = "foo: bar\n"
    new_yaml, changed = wid.ensure_widget_ids(no_layout)
    R.nok(changed)
    return R.eq(new_yaml, no_layout)
  end)
  return R.it("est idempotent", function()
    local once, first_changed = wid.ensure_widget_ids(YAML_TWO_WIDGETS)
    R.ok(first_changed, 'premier passage modifie')
    local twice, second_changed = wid.ensure_widget_ids(once)
    R.nok(second_changed, 'second passage sans changement')
    return R.eq(twice, once, 'texte stable')
  end)
end)
