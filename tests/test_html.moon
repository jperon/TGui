-- tests/test_html.moon
-- Tests backend/html.lua and the convention used by its callers.
--
-- html.lua stays generic (it also produces XML): an element without content
-- is rendered as a self-closing tag (`<div id="a"/>`), which is valid XML.
-- In HTML, `<div/>` is NOT closed: the browser treats it as an opening tag
-- and swallows the following markup. So in HTML documents the caller must
-- pass an empty string child for every empty non-void element:
--
--   H.br!                     -> <br/>        (void element)
--   H.div {id: 'a'}           -> <div id="a"/> (invalid in HTML)
--   H.div {id: 'a', ''}       -> <div id="a"></div>
--
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

R.describe 'html.lua — convention d’écriture', ->
  R.it 'self-closes a void element written without argument', ->
    R.eq H.br!, '<br/>'

  R.it 'self-closes a void element with attributes', ->
    R.eq H.input({ type: 'text' }), '<input type="text"/>'

  R.it 'self-closes any element given no content (generic, XML-friendly)', ->
    R.eq H.div({ id: 'a' }), '<div id="a"/>'

  R.it 'closes an element whose only child is the empty string', ->
    R.eq H.div({ id: 'a', '' }), '<div id="a"></div>'

  R.it 'closes an empty element without attribute given an empty string', ->
    R.eq H.div({ '' }), '<div></div>'

  R.it 'does not change the rendering of elements with content', ->
    R.eq H.p({ 'hello' }), '<p>hello</p>'

  R.it 'nests quoted children', ->
    R.eq H.div({ id: 'outer', H.span({ '' }) }), '<div id="outer"><span></span></div>'

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
