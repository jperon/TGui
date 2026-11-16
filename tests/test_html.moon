-- tests/test_html.moon
-- Tests backend/html.lua: only HTML void elements may be rendered as
-- self-closing tags. In HTML (unlike XHTML), `<div/>` is not closed: the
-- browser treats it as an opening tag and swallows the following markup.
-- Regression: `H.div {id: 'widget-manifest-form', class: '… hidden'}`
-- (backend/ui/widget_modal.moon) used to emit `<div …/>`, which hid the
-- data-view editor (#dv-name) from the SPA.

R = require 'tests.runner'
H = require 'html'

VOID = {
  area: true, base: true, br: true, col: true, embed: true, hr: true,
  img: true, input: true, link: true, meta: true, source: true,
  track: true, wbr: true,
}

_is_word = (c) -> c\match '[%w%-]'

-- Collect the tag names of every self-closing tag of a chunk of markup.
-- Quoted attribute values are skipped: the page embeds an SVG data URI
-- (`ICON` in backend/index.moon) whose `<rect/>` is SVG, not HTML.
self_closing_tags = (markup) ->
  names = {}
  tag_name = nil
  quote = nil
  in_tag = false
  i = 1
  n = #markup
  while i <= n
    c = markup\sub i, i
    if in_tag
      if quote
        quote = nil if c == quote
      elseif c == '"' or c == "'"
        quote = c
      elseif c == '>'
        table.insert names, tag_name if tag_name and markup\sub(i - 1, i - 1) == '/'
        in_tag = false
      elseif not tag_name and c\match '%a'
        j = i
        while j <= n and _is_word markup\sub j, j
          j += 1
        tag_name = markup\sub i, j - 1
        i = j - 1
    elseif c == '<'
      in_tag = true
      tag_name = nil
      quote = nil
    i += 1
  names

non_void_self_closing = (markup) ->
  bad = {}
  for name in *self_closing_tags markup
    table.insert bad, name unless VOID[name]
  bad

R.describe 'html.lua — auto-fermeture', ->
  R.it 'renders an empty div with an explicit closing tag', ->
    R.eq H.div({ id: 'a' }), '<div id="a"></div>'

  R.it 'renders an empty div without attribute with an explicit closing tag', ->
    R.eq H.div({}), '<div></div>'

  R.it 'keeps void elements self-closed', ->
    R.eq H.input({ type: 'text' }), '<input type="text"/>'

  R.it 'renders every void element self-closed', ->
    for name in pairs VOID
      got = (H[name] {})
      R.eq got, "<#{name}/>", name

  R.it 'renders an empty non-void element with attributes as open+close', ->
    R.eq H.span({ class: 'x' }), '<span class="x"></span>'

  R.it 'renders a nested empty element with a closing tag', ->
    R.eq H.div({ id: 'outer', H.span {} }), '<div id="outer"><span></span></div>'

  R.it 'renders an empty script with an explicit closing tag', ->
    R.eq H.script({ src: '/x.js' }), '<script src="/x.js"></script>'

  R.it 'does not change the rendering of elements with content', ->
    R.eq H.p({ 'hello' }), '<p>hello</p>'

R.describe 'html.lua — page complète', ->
  R.it 'the full SPA markup contains no self-closing non-void tag', ->
    render = require 'index'
    page = render!
    R.ok type(page) == 'string' and #page > 0, 'page rendered'
    bad = non_void_self_closing page
    R.eq #bad, 0, "self-closing non-void tags (#{table.concat bad, ', '})"

  R.it 'the full SPA markup self-closes void elements only', ->
    render = require 'index'
    tags = self_closing_tags render!
    R.ok #tags > 0, 'some self-closing tags are expected (void elements)'
    for name in *tags
      R.ok VOID[name], "self-closing <#{name}/> is a void element"

  R.it 'the widget manifest form placeholder is not self-closed', ->
    render = require 'index'
    page = render!
    R.nok (page\match 'widget%-manifest%-form"/>'), 'no self-closed manifest form'
    R.matches page, '<div[^>]-id="widget%-manifest%-form"[^>]*></div>',
      'manifest form rendered as <div …></div>'
