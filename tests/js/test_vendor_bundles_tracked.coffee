# tests/js/test_vendor_bundles_tracked.coffee — guard against 404 vendor bundles
# Every /vendor/... path referenced by the page must be a git-tracked file.
# Otherwise a fresh clone (CI, new install) serves it as 404 and the page breaks
# silently (e.g. "SortableJS is not defined on window").
# See AGENTS.md, "Vendor frontend".
#
# Bundle chargés à la demande (spec widgets personnalisés §7) : ils ne sont pas
# dans la page, mais frontend/src/views/plugin_runtimes.js les insère plus tard ;
# ils doivent donc être committés tout autant. La liste LAZY_SCRIPT_SRCS de
# backend/ui/scripts.moon est contrôlée séparément.

{ execFileSync } = require 'child_process'
path = require 'path'
fs   = require 'fs'
{ describe, it, assert, summary } = require './runner'

ROOT = path.resolve __dirname, '..', '..'

# Sources that reference the static vendor assets: the <script src> list and
# the <link rel="stylesheet"> tags of the SPA shell.
PAGE_SOURCES = [
  'backend/ui/scripts.moon'
  'backend/index.moon'
]

VENDOR_PATH_RE = /\/vendor\/[A-Za-z0-9_.-]+/g

# Union of the /vendor/... paths found in the page sources, sorted.
extractVendorPaths = ->
  seen = {}
  for rel in PAGE_SOURCES
    src = fs.readFileSync path.join(ROOT, rel), 'utf8'
    for found in (src.match VENDOR_PATH_RE) or []
      seen[found] = true
  Object.keys(seen).sort()

# /vendor/... paths declared in LAZY_SCRIPT_SRCS (on-demand bundles).
extractLazyVendorPaths = ->
  src = fs.readFileSync path.join(ROOT, 'backend/ui/scripts.moon'), 'utf8'
  block = src.match /LAZY_SCRIPT_SRCS\s*=\s*\{([\s\S]*?)\}/
  assert block, 'LAZY_SCRIPT_SRCS introuvable dans backend/ui/scripts.moon'
  found = block[1].match VENDOR_PATH_RE or []
  found.sort()

# True when git tracks +filePath+ in this checkout.
isTracked = (filePath) ->
  try
    execFileSync 'git', ['ls-files', '--error-unmatch', '--', filePath],
      cwd: ROOT
      stdio: 'pipe'
    true
  catch e
    false

assertTracked = (vendorPath, why) ->
  filePath = path.posix.join 'frontend', vendorPath
  assert isTracked(filePath),
    "le bundle #{vendorPath} #{why} mais #{filePath} " +
    "n'est pas suivi par git : un clone neuf le recevra en 404. " +
    "Committer #{filePath} et l'autoriser dans .gitignore " +
    '(voir AGENTS.md, « Vendor frontend »).'

describe 'Vendor bundles loaded by the page', ->
  vendorPaths = extractVendorPaths()

  it 'extrait des chemins /vendor/ depuis les sources de la page', ->
    assert vendorPaths.length > 0,
      "aucun chemin /vendor/ extrait de #{PAGE_SOURCES.join ', '} : " +
      'le motif VENDOR_PATH_RE du test est cassé'

  for vendorPath in vendorPaths
    do (vendorPath) ->
      it "#{vendorPath} est suivi par git", ->
        assertTracked vendorPath, 'est référencé par la page'

describe 'Vendor bundles loaded on demand (LAZY_SCRIPT_SRCS)', ->
  lazyPaths = extractLazyVendorPaths()

  it 'LAZY_SCRIPT_SRCS déclare le bundle des compilateurs de widgets', ->
    assert lazyPaths.length > 0,
      'LAZY_SCRIPT_SRCS est vide : les compilateurs de widgets ne seraient ' +
      'plus chargeables à la demande'
    assert '/vendor/plugin-runtime.bundle.js' in lazyPaths,
      "plugin-runtime.bundle.js absent de LAZY_SCRIPT_SRCS (#{lazyPaths.join ', '})"

  for vendorPath in lazyPaths
    do (vendorPath) ->
      it "#{vendorPath} est suivi par git", ->
        assertTracked vendorPath, 'est chargé à la demande'

summary()
