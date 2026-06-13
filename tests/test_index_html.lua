local R = require('tests.runner')
local render = require('index')
local html = render()
local required_scripts = {
  '/vendor/tui-grid.bundle.js',
  '/vendor/jsyaml.bundle.js',
  '/vendor/codemirror.bundle.js',
  '/vendor/sortablejs.bundle.js',
  '/vendor/plugin-runtime.bundle.js'
}
return R.describe("index.html — bundles vendor", function()
  for _index_0 = 1, #required_scripts do
    local src = required_scripts[_index_0]
    R.it("inclut " .. tostring(src), function()
      return R.ok(html:find(src, 1, true) ~= nil, "script manquant : " .. tostring(src))
    end)
  end
end)
