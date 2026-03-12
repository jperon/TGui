#!/usr/bin/env moon
-- Summary: Build localized docs from English Markdown and PO catalogs without po4a.
-- Responsibilities:
-- - Generate po/tdb-docs.pot from doc/en markdown sources.
-- - Build doc/fr markdown from po/fr.po with English fallback.
-- - Fail on encoding regressions (C1 controls and known mojibake markers).
-- Depends on:
-- - doc/en/*.md and doc/en/dev/*.md
-- - po/fr.po and po/tdb-docs.pot
-- Used by:
-- - Makefile targets doc-po-update, doc-po-build and doc-check.

DOC_EN_FILES = {
  'doc/en/README.md'
  'doc/en/get-started.md'
  'doc/en/reference.md'
  'doc/en/api.md'
  'doc/en/dev.md'
  'doc/en/dev/architecture.md'
  'doc/en/dev/runtime.md'
  'doc/en/dev/graphql.md'
  'doc/en/dev/frontend.md'
  'doc/en/dev/tests.md'
}

trim = (s) ->
  return '' unless s
  s = s\gsub '^%s+', ''
  s\gsub '%s+$', ''

shell_quote = (s) ->
  "'#{tostring(s)\gsub("'", "'\\''")}'"

file_exists = (path) ->
  f = io.open path, 'r'
  return false unless f
  f\close!
  true

read_text = (path) ->
  f, err = io.open path, 'r'
  error "Cannot read file: #{path} (#{err or 'unknown error'})" unless f
  content = f\read '*a'
  f\close!
  content

write_text = (path, content) ->
  f, err = io.open path, 'w'
  error "Cannot write file: #{path} (#{err or 'unknown error'})" unless f
  f\write content
  f\close!

ensure_dir_for_file = (path) ->
  dir = path\match('^(.*)/[^/]+$') or '.'
  os.execute "mkdir -p #{shell_quote(dir)}"

has_c1_controls = (text) ->
  i = 1
  while i <= #text
    b1 = text\byte i
    if b1 == 0xC2 and i < #text
      b2 = text\byte i + 1
      return true if b2 >= 0x80 and b2 <= 0x9F
      i += 2
    else
      i += 1
  false

-- Mojibake detection via byte-level patterns built with string.char.
-- Double-encoded UTF-8 through CP1252 produces sequences like C3 A2 C2 80 C2 xx.
MOJIBAKE_PREFIXES = {
  string.char(0xC3, 0xA2, 0xC2, 0x80)
  string.char(0xC3, 0xA2, 0xC2, 0x86)
  string.char(0xC3, 0xA2, 0xC2, 0x96)
  string.char(0xC3, 0xA2, 0xC2, 0x9C)
  string.char(0xC3, 0x83, 0xC2)
}

has_mojibake = (text) ->
  for prefix in *MOJIBAKE_PREFIXES
    return true if text\find prefix, 1, true
  false

is_clean_text = (text) ->
  not has_c1_controls(text) and not has_mojibake(text)

escape_po = (s) ->
  s = s\gsub '\\', '\\\\'
  s = s\gsub '"', '\\"'
  s = s\gsub '\t', '\\t'
  s = s\gsub '\r', '\\r'
  s\gsub '\n', '\\n'

unescape_po = (s) ->
  s = s\gsub '\\n', '\n'
  s = s\gsub '\\t', '\t'
  s = s\gsub '\\r', '\r'
  s = s\gsub '\\"', '"'
  s\gsub '\\\\', '\\'

parse_po = (path) ->
  return {} unless file_exists path
  text = read_text path

  translations = {}
  current_msgid = nil
  current_msgstr = nil
  state = nil

  flush = ->
    if current_msgid and current_msgid != ''
      translations[current_msgid] = current_msgstr or ''
    current_msgid = nil
    current_msgstr = nil
    state = nil

  for line in text\gmatch '([^\n]*)\n?'
    if line\match '^%s*$'
      flush!
      continue

    if line\match '^#'
      continue

    if line\match '^msgid%s+"'
      flush!
      chunk = line\match '^msgid%s+"(.*)"$' or ''
      current_msgid = unescape_po chunk
      current_msgstr = ''
      state = 'msgid'
      continue

    if line\match '^msgstr%s+"'
      chunk = line\match '^msgstr%s+"(.*)"$' or ''
      current_msgstr = unescape_po chunk
      state = 'msgstr'
      continue

    if line\match '^"'
      chunk = line\match '^"(.*)"$' or ''
      if state == 'msgid'
        current_msgid = (current_msgid or '') .. unescape_po(chunk)
      elseif state == 'msgstr'
        current_msgstr = (current_msgstr or '') .. unescape_po(chunk)
      continue

  flush!
  translations

collect_source_entries = ->
  refs_by_msgid = {}
  order = {}

  remember = (msgid, ref) ->
    return if msgid\match '^%s*$'
    entry = refs_by_msgid[msgid]
    unless entry
      entry = {
        refs: {}
        refs_set: {}
      }
      refs_by_msgid[msgid] = entry
      table.insert order, msgid

    unless entry.refs_set[ref]
      entry.refs_set[ref] = true
      table.insert entry.refs, ref

  for en_path in *DOC_EN_FILES
    text = read_text en_path
    line_no = 0
    for line in text\gmatch '([^\n]*)\n?'
      line_no += 1
      remember line, "#{en_path}:#{line_no}"

  refs_by_msgid, order

cmd_update_pot = ->
  refs_by_msgid, order = collect_source_entries!

  out = {
    'msgid ""'
    'msgstr ""'
    '"Project-Id-Version: tdb-docs\\n"'
    '"Content-Type: text/plain; charset=UTF-8\\n"'
    '"Content-Transfer-Encoding: 8bit\\n"'
    ''
  }

  for msgid in *order
    entry = refs_by_msgid[msgid]
    refs = table.concat entry.refs, ' '
    table.insert out, "#: #{refs}"
    table.insert out, "msgid \"#{escape_po(msgid)}\""
    table.insert out, 'msgstr ""'
    table.insert out, ''

  ensure_dir_for_file 'po/tdb-docs.pot'
  write_text 'po/tdb-docs.pot', table.concat(out, '\n')

  unless file_exists 'po/fr.po'
    write_text 'po/fr.po', table.concat({
      'msgid ""'
      'msgstr ""'
      '"Project-Id-Version: tdb-docs\\n"'
      '"Content-Type: text/plain; charset=UTF-8\\n"'
      '"Content-Transfer-Encoding: 8bit\\n"'
      ''
    }, '\n')

  print 'doc_localize: updated po/tdb-docs.pot'

cmd_build_fr = ->
  translations = parse_po 'po/fr.po'

  for en_path in *DOC_EN_FILES
    fr_path = en_path\gsub '^doc/en/', 'doc/fr/'
    text = read_text en_path
    had_trailing_newline = text\sub(-1) == '\n'

    out_lines = {}
    for line in text\gmatch '([^\n]*)\n?'
      translated = line
      candidate = translations[line]
      if candidate and candidate != '' and is_clean_text(candidate)
        translated = candidate
      table.insert out_lines, translated

    output = table.concat out_lines, '\n'
    output = "#{output}\n" if had_trailing_newline and output\sub(-1) != '\n'

    if not is_clean_text(output)
      io.stderr\write "WARNING: encoding issue in #{fr_path}, using English fallback\n"
      output = text

    ensure_dir_for_file fr_path
    write_text fr_path, output

  print 'doc_localize: generated doc/fr from doc/en + po/fr.po (fallback enabled)'

cmd_check_encoding = ->
  errors = {}

  for path in *{
    'doc/fr/README.md'
    'doc/fr/get-started.md'
    'doc/fr/reference.md'
    'doc/fr/api.md'
    'doc/fr/dev.md'
    'doc/fr/dev/architecture.md'
    'doc/fr/dev/runtime.md'
    'doc/fr/dev/graphql.md'
    'doc/fr/dev/frontend.md'
    'doc/fr/dev/tests.md'
  }
    unless file_exists path
      table.insert errors, "missing file: #{path}"
      continue

    text = read_text path
    table.insert errors, "C1 control detected in #{path}" if has_c1_controls text
    table.insert errors, "mojibake marker detected in #{path}" if has_mojibake text

  if #errors > 0
    io.stderr\write "doc_localize encoding check failed (#{#errors} issue(s)):\n"
    for err in *errors
      io.stderr\write "- #{err}\n"
    os.exit 1

  print 'doc_localize: encoding check OK'

main = ->
  command = arg and arg[1] or ''

  if command == 'update-pot'
    cmd_update_pot!
  elseif command == 'build-fr'
    cmd_build_fr!
  elseif command == 'check-encoding'
    cmd_check_encoding!
  else
    io.stderr\write "Usage: tarantool scripts/doc_localize.lua [update-pot|build-fr|check-encoding]\n"
    os.exit 1

main!
os.exit 0
