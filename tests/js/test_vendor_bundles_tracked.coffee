# tests/js/test_vendor_bundles_tracked.coffee — guard against 404 vendor bundles
# Every /vendor/... path referenced by the page must be a git-tracked file.
# Otherwise a fresh clone (CI, new install) serves it as 404 and the page breaks
# silently (e.g. "SortableJS is not defined on window").
# See AGENTS.md, "Vendor frontend".

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

# True when git tracks +filePath+ in this checkout.
isTracked = (filePath) ->
  try
    execFileSync 'git', ['ls-files', '--error-unmatch', '--', filePath],
      cwd: ROOT
      stdio: 'pipe'
    true
  catch e
    false

describe 'Vendor bundles loaded by the page', ->
  vendorPaths = extractVendorPaths()

  it 'extrait des chemins /vendor/ depuis les sources de la page', ->
    assert vendorPaths.length > 0,
      "aucun chemin /vendor/ extrait de #{PAGE_SOURCES.join ', '} : " +
      'le motif VENDOR_PATH_RE du test est cassé'

  for vendorPath in vendorPaths
    do (vendorPath) ->
      it "#{vendorPath} est suivi par git", ->
        filePath = path.posix.join 'frontend', vendorPath
        assert isTracked(filePath),
          "le bundle #{vendorPath} est chargé par la page mais #{filePath} " +
          "n'est pas suivi par git : un clone neuf le recevra en 404. " +
          "Committer #{filePath} et l'autoriser dans .gitignore " +
          '(voir AGENTS.md, « Vendor frontend »).'

summary()
