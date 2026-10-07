# tests/js/test_view_helpers_dedup.coffee
# T11 refactor guard: AppViewHelpers must not define any key twice, and every
# AppViewHelpers._xxx call site in frontend/src must have a definition.
#
# Pre-existing gaps (called but never defined before T11 either — not invented here):
#   _populateGroupByOptions, _confirmAddWidget, _closeAddWidgetModal
# These were only reachable from dead/discarded code or from a missing resolver
# in _initializeWidgetModal; the refactor keeps that runtime behaviour.

fs = require 'fs'
path = require 'path'
{ describe, it, eq, assert, summary } = require './runner'

SRC_DIR = path.join __dirname, '../../frontend/src'
HELPERS_PREFIX = 'app_view_helpers'

# Pre-existing call sites without definitions (documented, not invented)
ALLOW_MISSING = [
  '_populateGroupByOptions'
  '_confirmAddWidget'
  '_closeAddWidgetModal'
]

listHelperFiles = ->
  prefixRe = new RegExp "^#{HELPERS_PREFIX}.*\\.coffee$"
  fs.readdirSync SRC_DIR
    .filter (f) -> prefixRe.test f
    .sort()
    .map (f) -> path.join SRC_DIR, f

# Extract keys defined on window.AppViewHelpers in a helper source.
# Matches:
#   window.AppViewHelpers =\n  key: ...
#   Object.assign window.AppViewHelpers,\n  key: ...
#   window.AppViewHelpers.key = ...
extractDefinedKeys = (content, file) ->
  keys = []
  lines = content.split '\n'
  i = 0
  while i < lines.length
    line = lines[i]
    if /^window\.AppViewHelpers\s*=\s*$/.test(line) or /^Object\.assign\s+window\.AppViewHelpers\s*,\s*$/.test(line)
      i++
      heredoc = false
      while i < lines.length
        l = lines[i]
        # track """ / ''' heredocs: column-0 lines inside them must not end the object
        tripleDouble = (l.match(new RegExp '"""', 'g') or []).length
        tripleSingle = (l.match(new RegExp "'''", 'g') or []).length
        quotes = tripleDouble + tripleSingle
        if quotes % 2 == 1
          heredoc = not heredoc
          m = l.match /^  ([A-Za-z_][A-Za-z0-9_]*)\s*:/
          keys.push m[1] if m and not heredoc
          i++
          continue
        if heredoc
          i++
          continue
        if l.trim() == ''
          i++
          continue
        if l[0] != ' '
          break
        m = l.match /^  ([A-Za-z_][A-Za-z0-9_]*)\s*:/
        keys.push m[1] if m
        i++
    else
      m = line.match /^window\.AppViewHelpers\.([A-Za-z_][A-Za-z0-9_]*)\s*=/
      keys.push m[1] if m
    i++
  { file, keys }

# Collect AppViewHelpers.<name> call sites in frontend/src (excluding compiled .js)
extractCallSites = ->
  calls = []
  walk = (dir) ->
    for entry in fs.readdirSync(dir)
      full = path.join dir, entry
      st = fs.statSync full
      if st.isDirectory()
        walk full
      else if entry.match /\.coffee$/
        content = fs.readFileSync full, 'utf8'
        re = /(?:window\.)?AppViewHelpers\.([A-Za-z_][A-Za-z0-9_]*)/g
        while (m = re.exec(content))
          calls.push { name: m[1], file: full }
  walk SRC_DIR
  calls

describe 'AppViewHelpers source integrity', ->
  helpers = listHelperFiles()
  allKeys = []
  for f in helpers
    content = fs.readFileSync f, 'utf8'
    allKeys.push extractDefinedKeys(content, f)

  it 'trouve les fichiers app_view_helpers*.coffee', ->
    assert helpers.length >= 2, "au moins 2 fichiers attendus, trouvé #{helpers.length}"

  it 'n\'a aucune clé définie deux fois sur AppViewHelpers', ->
    seen = {}
    dups = []
    for { file, keys } in allKeys
      for k in keys
        if seen[k]
          dups.push "#{k} (#{seen[k]} et #{file})"
        else
          seen[k] = file
    eq dups.length, 0, "clés dupliquées: #{dups.join(', ')}"

  it 'n\'utilise pas de module.exports de fichier dans les helpers navigateur', ->
    offenders = []
    for f in helpers
      content = fs.readFileSync f, 'utf8'
      lines = content.split '\n'
      for line, idx in lines
        # ignore module.exports inside a plugin template string (scriptCode heredoc)
        continue if line.match /^\s*module\.exports\s*=/
        # real file-level export would be at column 0 outside a string; after
        # CoffeeScript compile it never appears. In .coffee, a top-level
        # `module.exports =` at column 0 that is NOT inside """ is an offender.
        if /^module\.exports\s*=/.test(line)
          # check if we are inside a """ heredoc by scanning upward
          inHeredoc = false
          for j in [0...idx]
            if lines[j].match /"""\s*$/
              inHeredoc = not inHeredoc
          offenders.push "#{f}:#{idx+1}" unless inHeredoc
    eq offenders.length, 0, "module.exports hors heredoc: #{offenders.join(', ')}"

  it 'définit chaque fonction appelée via AppViewHelpers (sauf lacunes préexistantes)', ->
    defined = {}
    for { keys } in allKeys
      for k in keys
        defined[k] = true
    missing = {}
    for { name, file } in extractCallSites()
      continue if defined[name]
      continue if name in ALLOW_MISSING
      missing[name] ?= []
      missing[name].push path.basename(file)
    names = Object.keys(missing).sort()
    eq names.length, 0, "appels sans définition: #{names.map((n) -> n + ' (' + missing[n].join(',') + ')').join(', ')}"

  it 'garde les lacunes préexistantes documentées (pas de fuite silencieuse)', ->
    # _populateGroupByOptions is called from _initializeWidgetModal but was
    # never defined before T11 either. Allowlist must stay explicit.
    assert '_populateGroupByOptions' in ALLOW_MISSING
    assert '_confirmAddWidget' in ALLOW_MISSING
    assert '_closeAddWidgetModal' in ALLOW_MISSING

summary()
