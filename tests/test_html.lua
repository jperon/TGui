local R = require('tests.runner')
local H = require('html')
local VOID = {
  area = true,
  base = true,
  br = true,
  col = true,
  embed = true,
  hr = true,
  img = true,
  input = true,
  link = true,
  meta = true,
  source = true,
  track = true,
  wbr = true
}
local _is_word
_is_word = function(c)
  return c:match('[%w%-]')
end
local self_closing_tags
self_closing_tags = function(markup)
  local names = { }
  local tag_name = nil
  local quote = nil
  local in_tag = false
  local i = 1
  local n = #markup
  while i <= n do
    local c = markup:sub(i, i)
    if in_tag then
      if quote then
        if c == quote then
          quote = nil
        end
      elseif c == '"' or c == "'" then
        quote = c
      elseif c == '>' then
        if tag_name and markup:sub(i - 1, i - 1) == '/' then
          table.insert(names, tag_name)
        end
        in_tag = false
      elseif not tag_name and c:match('%a') then
        local j = i
        while j <= n and _is_word(markup:sub(j, j)) do
          j = j + 1
        end
        tag_name = markup:sub(i, j - 1)
        i = j - 1
      end
    elseif c == '<' then
      in_tag = true
      tag_name = nil
      quote = nil
    end
    i = i + 1
  end
  return names
end
local non_void_self_closing
non_void_self_closing = function(markup)
  local bad = { }
  local _list_0 = self_closing_tags(markup)
  for _index_0 = 1, #_list_0 do
    local name = _list_0[_index_0]
    if not (VOID[name]) then
      table.insert(bad, name)
    end
  end
  return bad
end
R.describe('html.lua — auto-fermeture', function()
  R.it('renders an empty div with an explicit closing tag', function()
    return R.eq(H.div({
      id = 'a'
    }), '<div id="a"></div>')
  end)
  R.it('renders an empty div without attribute with an explicit closing tag', function()
    return R.eq(H.div({ }), '<div></div>')
  end)
  R.it('keeps void elements self-closed', function()
    return R.eq(H.input({
      type = 'text'
    }), '<input type="text"/>')
  end)
  R.it('renders every void element self-closed', function()
    for name in pairs(VOID) do
      local got = (H[name]({ }))
      R.eq(got, "<" .. tostring(name) .. "/>", name)
    end
  end)
  R.it('renders an empty non-void element with attributes as open+close', function()
    return R.eq(H.span({
      class = 'x'
    }), '<span class="x"></span>')
  end)
  R.it('renders a nested empty element with a closing tag', function()
    return R.eq(H.div({
      id = 'outer',
      H.span({ })
    }), '<div id="outer"><span></span></div>')
  end)
  R.it('renders an empty script with an explicit closing tag', function()
    return R.eq(H.script({
      src = '/x.js'
    }), '<script src="/x.js"></script>')
  end)
  return R.it('does not change the rendering of elements with content', function()
    return R.eq(H.p({
      'hello'
    }), '<p>hello</p>')
  end)
end)
return R.describe('html.lua — page complète', function()
  R.it('the full SPA markup contains no self-closing non-void tag', function()
    local render = require('index')
    local page = render()
    R.ok(type(page) == 'string' and #page > 0, 'page rendered')
    local bad = non_void_self_closing(page)
    return R.eq(#bad, 0, "self-closing non-void tags (" .. tostring(table.concat(bad, ', ')) .. ")")
  end)
  R.it('the full SPA markup self-closes void elements only', function()
    local render = require('index')
    local tags = self_closing_tags(render())
    R.ok(#tags > 0, 'some self-closing tags are expected (void elements)')
    for _index_0 = 1, #tags do
      local name = tags[_index_0]
      R.ok(VOID[name], "self-closing <" .. tostring(name) .. "/> is a void element")
    end
  end)
  return R.it('the widget manifest form placeholder is not self-closed', function()
    local render = require('index')
    local page = render()
    R.nok((page:match('widget%-manifest%-form"/>')), 'no self-closed manifest form')
    return R.matches(page, '<div[^>]-id="widget%-manifest%-form"[^>]*></div>', 'manifest form rendered as <div …></div>')
  end)
end)
