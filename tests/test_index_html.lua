local R = require('tests.runner')
local render = require('index')
local html = render()
local scripts = require('ui.scripts')
local required_scripts = {
  '/vendor/tui-grid.bundle.js',
  '/vendor/jsyaml.bundle.js',
  '/vendor/codemirror.bundle.js',
  '/vendor/sortablejs.bundle.js'
}
R.describe("index.html — bundles vendor", function()
  for _index_0 = 1, #required_scripts do
    local src = required_scripts[_index_0]
    R.it("inclut " .. tostring(src), function()
      return R.ok(html:find(src, 1, true) ~= nil, "script manquant : " .. tostring(src))
    end)
  end
end)
return R.describe("index.html — bundles chargés à la demande", function()
  R.it("ui.scripts exporte LAZY_SCRIPT_SRCS", function()
    return R.eq(type(scripts.LAZY_SCRIPT_SRCS), 'table', 'LAZY_SCRIPT_SRCS')
  end)
  R.it("le bundle des compilateurs de widgets n'est pas dans la page", function()
    local _list_0 = (scripts.LAZY_SCRIPT_SRCS or { })
    for _index_0 = 1, #_list_0 do
      local src = _list_0[_index_0]
      R.ok(html:find(src, 1, true) == nil, "bundle chargé à la demande présent dans la page : " .. tostring(src))
    end
  end)
  return R.it("le bundle des compilateurs est déclaré en lazy", function()
    local found = false
    local _list_0 = (scripts.LAZY_SCRIPT_SRCS or { })
    for _index_0 = 1, #_list_0 do
      local src = _list_0[_index_0]
      if src == '/vendor/plugin-runtime.bundle.js' then
        found = true
      end
    end
    return R.ok(found, 'plugin-runtime.bundle.js absent de LAZY_SCRIPT_SRCS')
  end)
end)
