-- tests/test_lexer.moon
-- Tests du lexer GraphQL (graphql/lexer.moon).
-- Aucune dépendance Tarantool — peut tourner avec `lua` ou `tarantool`.

R = require 'tests.runner'
{ :tokenize, :TOKEN_TYPES } = require 'graphql.lexer'

-- Helpers
tok_types = (src) ->
  [t.type for t in *tokenize src]

tok_values = (src) ->
  [t.value for t in *tokenize src]

first = (src) ->
  tokenize(src)[1]

R.describe "Lexer — tokens de base", ->
  R.it "source vide → un seul EOF", ->
    tokens = tokenize ""
    R.eq #tokens, 1
    R.eq tokens[1].type, 'EOF'

  R.it "identifiant simple", ->
    t = first "hello"
    R.eq t.type, 'NAME'
    R.eq t.value, 'hello'

  R.it "mot-clé query est un NAME", ->
    R.eq first("query").type, 'NAME'
    R.eq first("query").value, 'query'

  R.it "mot-clé mutation est un NAME", ->
    R.eq first("mutation").value, 'mutation'

  R.it "underscore dans l'identifiant", ->
    t = first "_my_field"
    R.eq t.type, 'NAME'
    R.eq t.value, '_my_field'

R.describe "Lexer — ponctuation", ->
  cases = {
    {'!',   'BANG'},
    {'$',   'DOLLAR'},
    {'(',   'PAREN_L'},
    {')',   'PAREN_R'},
    {'[',   'BRACKET_L'},
    {']',   'BRACKET_R'},
    {'{',   'BRACE_L'},
    {'}',   'BRACE_R'},
    {':',   'COLON'},
    {'=',   'EQUALS'},
    {'@',   'AT'},
    {'|',   'PIPE'},
    {'&',   'AMP'},
    {'...', 'SPREAD'},
  }
  for _, c in ipairs cases
    char          = c[1]
    expected_type = c[2]
    R.it "#{char} → #{expected_type}", ->
      R.eq (first char).type, expected_type

R.describe "Lexer — nombres", ->
  R.it "entier positif", ->
    t = first "42"
    R.eq t.type, 'INT'
    R.eq t.value, '42'

  R.it "entier négatif", ->
    t = first "-7"
    R.eq t.type, 'INT'
    R.eq t.value, '-7'

  R.it "zéro", ->
    t = first "0"
    R.eq t.type, 'INT'
    R.eq t.value, '0'

  R.it "flottant", ->
    t = first "3.14"
    R.eq t.type, 'FLOAT'
    R.eq t.value, '3.14'

  R.it "flottant négatif", ->
    t = first "-0.5"
    R.eq t.type, 'FLOAT'

  R.it "notation scientifique", ->
    t = first "1e10"
    R.eq t.type, 'FLOAT'

  R.it "notation scientifique avec exposant négatif", ->
    t = first "1.5E-3"
    R.eq t.type, 'FLOAT'

R.describe "Lexer — chaînes", ->
  R.it "chaîne simple", ->
    t = first '"hello"'
    R.eq t.type, 'STRING'
    R.eq t.value, 'hello'

  R.it "chaîne vide", ->
    t = first '""'
    R.eq t.type, 'STRING'
    R.eq t.value, ''

  R.it "chaîne avec échappement \\n", ->
    t = first '"a\\nb"'
    R.eq t.type, 'STRING'
    R.matches t.value, 'a'

  R.it "chaîne avec échappement \\t", ->
    t = first '"a\\tb"'
    R.eq t.type, 'STRING'

  R.it "block string (triple guillemets)", ->
    t = first '"""hello world"""'
    R.eq t.type, 'BLOCK_STRING'
    R.matches t.value, 'hello'

R.describe "Lexer — espaces et commentaires", ->
  R.it "les espaces sont ignorés", ->
    tokens = tokenize "   hello   "
    R.eq tokens[1].type, 'NAME'
    R.eq tokens[1].value, 'hello'

  R.it "les virgules sont ignorées", ->
    types = tok_types "a, b, c"
    R.eq types[1], 'NAME'
    R.eq types[2], 'NAME'
    R.eq types[3], 'NAME'
    R.eq types[4], 'EOF'

  R.it "les commentaires # sont ignorés", ->
    tokens = tokenize "# commentaire\nhello"
    R.eq tokens[1].type, 'NAME'
    R.eq tokens[1].value, 'hello'

  R.it "les sauts de ligne sont ignorés", ->
    tokens = tokenize "a\nb\nc"
    R.eq #tokens, 4  -- a, b, c, EOF

R.describe "Lexer — séquences mixtes", ->
  R.it "requête minimaliste { field }", ->
    types = tok_types "{ field }"
    R.eq types[1], 'BRACE_L'
    R.eq types[2], 'NAME'
    R.eq types[3], 'BRACE_R'
    R.eq types[4], 'EOF'

  R.it "champ avec argument (arg: 123)", ->
    types = tok_types "field(arg: 123)"
    R.eq types[1], 'NAME'    -- field
    R.eq types[2], 'PAREN_L'
    R.eq types[3], 'NAME'    -- arg
    R.eq types[4], 'COLON'
    R.eq types[5], 'INT'
    R.eq types[6], 'PAREN_R'

  R.it "type non-nul String!", ->
    types = tok_types "String!"
    R.eq types[1], 'NAME'
    R.eq types[2], 'BANG'

  R.it "liste [String]", ->
    types = tok_types "[String]"
    R.eq types[1], 'BRACKET_L'
    R.eq types[2], 'NAME'
    R.eq types[3], 'BRACKET_R'

  R.it "variable $var", ->
    types = tok_types "$var"
    R.eq types[1], 'DOLLAR'
    R.eq types[2], 'NAME'

  R.it "spread ...", ->
    t = first "..."
    R.eq t.type, 'SPREAD'
