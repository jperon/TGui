-- tests/test_lexer.moon
-- Tests for GraphQL lexer (graphql/lexer.moon).
-- No Tarantool dependency — can run with `lua` or `tarantool`.

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

  R.it "query keyword is a NAME", ->
    R.eq first("query").type, 'NAME'
    R.eq first("query").value, 'query'

  R.it "mutation keyword is a NAME", ->
    R.eq first("mutation").value, 'mutation'

  R.it "underscore in identifier", ->
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

  R.it "negative integer", ->
    t = first "-7"
    R.eq t.type, 'INT'
    R.eq t.value, '-7'

  R.it "zero", ->
    t = first "0"
    R.eq t.type, 'INT'
    R.eq t.value, '0'

  R.it "flottant", ->
    t = first "3.14"
    R.eq t.type, 'FLOAT'
    R.eq t.value, '3.14'

  R.it "negative float", ->
    t = first "-0.5"
    R.eq t.type, 'FLOAT'

  R.it "notation scientifique", ->
    t = first "1e10"
    R.eq t.type, 'FLOAT'

  R.it "scientific notation with negative exponent", ->
    t = first "1.5E-3"
    R.eq t.type, 'FLOAT'

R.describe "Lexer — strings", ->
  R.it "simple string", ->
    t = first '"hello"'
    R.eq t.type, 'STRING'
    R.eq t.value, 'hello'

  R.it "empty string", ->
    t = first '""'
    R.eq t.type, 'STRING'
    R.eq t.value, ''

  R.it "string with \\n escape", ->
    t = first '"a\\nb"'
    R.eq t.type, 'STRING'
    R.matches t.value, 'a'

  R.it "string with \\t escape", ->
    t = first '"a\\tb"'
    R.eq t.type, 'STRING'

  R.it "block string (triple quotes)", ->
    t = first '"""hello world"""'
    R.eq t.type, 'BLOCK_STRING'
    R.matches t.value, 'hello'

R.describe "Lexer — spaces and comments", ->
  R.it "spaces are ignored", ->
    tokens = tokenize "   hello   "
    R.eq tokens[1].type, 'NAME'
    R.eq tokens[1].value, 'hello'

  R.it "commas are ignored", ->
    types = tok_types "a, b, c"
    R.eq types[1], 'NAME'
    R.eq types[2], 'NAME'
    R.eq types[3], 'NAME'
    R.eq types[4], 'EOF'

  R.it "# comments are ignored", ->
    tokens = tokenize "# commentaire\nhello"
    R.eq tokens[1].type, 'NAME'
    R.eq tokens[1].value, 'hello'

  R.it "newlines are ignored", ->
    tokens = tokenize "a\nb\nc"
    R.eq #tokens, 4  -- a, b, c, EOF

R.describe "Lexer — mixed sequences", ->
  R.it "minimal query { field }", ->
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
