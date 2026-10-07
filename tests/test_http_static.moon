-- tests/test_http_static.moon
-- Task 3 — fichiers statiques : garde-fous anti-traversal de chemin.
-- Cadrage : docs/superpowers/plans/2026-10-07-etapes-0-1-agents-et-securite.md
-- (section « Task 3 ») et docs/superpowers/specs/2026-10-07-app-versioning-design.md §7
-- (« Fichiers statiques : vérifier et corriger le traversal de chemin
-- (FRONTEND_DIR .. req.path) — refuser .., chemins absolus, octets nuls »).
-- S'exécute dans l'instance de tests via `make test`.

R = require 'tests.runner'
http_server = require 'http_server'
{ :FRONTEND_DIR } = require 'core.config'

-- Requête factice minimale : serve_static ne lit que `req.path`.
mk_req = (path) -> { path: path, method: 'GET', headers: {} }

-- ────────────────────────────────────────────────────────────────────────────
R.describe "safe_static_path — assets frontend acceptés", ->

  R.it "accepte /src/app.js", ->
    R.eq http_server.safe_static_path('/src/app.js'), "#{FRONTEND_DIR}/src/app.js"

  R.it "accepte /css/app.css", ->
    R.eq http_server.safe_static_path('/css/app.css'), "#{FRONTEND_DIR}/css/app.css"

  R.it "accepte /vendor/tui-grid.bundle.js", ->
    R.eq http_server.safe_static_path('/vendor/tui-grid.bundle.js'),
      "#{FRONTEND_DIR}/vendor/tui-grid.bundle.js"

-- ────────────────────────────────────────────────────────────────────────────
R.describe "safe_static_path — traversal refusé", ->

  R.it "refuse /../backend/init.lua", ->
    R.is_nil http_server.safe_static_path('/../backend/init.lua')

  R.it "refuse /src/../../etc/passwd", ->
    R.is_nil http_server.safe_static_path('/src/../../etc/passwd')

  R.it "refuse la variante encodée %2e%2e", ->
    R.is_nil http_server.safe_static_path('/src/%2e%2e/etc/passwd')

  R.it "refuse la variante encodée %2E%2E (majuscules)", ->
    R.is_nil http_server.safe_static_path('/src/%2E%2E/etc/passwd')

  R.it "refuse le double slash //", ->
    R.is_nil http_server.safe_static_path('/vendor//app.js')

  R.it "refuse l'octet nul (troncature de chemin côté C)", ->
    R.is_nil http_server.safe_static_path('/src/app.js\0.png')

  R.it "refuse un chemin UNC (backslash)", ->
    R.is_nil http_server.safe_static_path('\\\\server\\share\\app.js')

-- ────────────────────────────────────────────────────────────────────────────
R.describe "safe_static_path — chemins absolus refusés", ->
-- « Chemin absolu » = tout ce qui n'est pas un chemin d'URL enraciné sous
-- FRONTEND_DIR : URI absolue (forme absolute-form d'une requête proxy),
-- lettre de lecteur Windows, chemin relatif.

  R.it "refuse l'URI absolue http://127.0.0.1/etc/passwd", ->
    R.is_nil http_server.safe_static_path('http://127.0.0.1/etc/passwd')

  R.it "refuse la lettre de lecteur C:/Windows/win.ini", ->
    R.is_nil http_server.safe_static_path('C:/Windows/win.ini')

  R.it "refuse le chemin relatif src/app.js", ->
    R.is_nil http_server.safe_static_path('src/app.js')

  R.it "refuse /../etc/passwd (absolu hors de la racine)", ->
    R.is_nil http_server.safe_static_path('/../etc/passwd')

-- ────────────────────────────────────────────────────────────────────────────
R.describe "serve_static — jamais de contenu hors de FRONTEND_DIR", ->

  R.it "contrôle : /css/app.css est servi (200)", ->
    res = http_server.serve_static mk_req '/css/app.css'
    R.eq res.status, 200

  R.it "/../backend/init.lua -> 404, jamais le contenu", ->
    res = http_server.serve_static mk_req '/../backend/init.lua'
    R.eq res.status, 404
    R.nok tostring(res.body)\find 'package.path', 1, true

  R.it "/src/%2e%2e/../etc/passwd -> 404", ->
    res = http_server.serve_static mk_req '/src/%2e%2e/etc/passwd'
    R.eq res.status, 404

  R.it "l'octet nul ne tronque pas le chemin -> 404", ->
    res = http_server.serve_static mk_req '/src/app.js\0.png'
    R.eq res.status, 404

  R.it "/etc/passwd -> 404 (le join reste sous FRONTEND_DIR)", ->
    res = http_server.serve_static mk_req '/etc/passwd'
    R.eq res.status, 404
