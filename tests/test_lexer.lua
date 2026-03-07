local R = require('tests.runner')
local tokenize, TOKEN_TYPES
do
  local _obj_0 = require('graphql.lexer')
  tokenize, TOKEN_TYPES = _obj_0.tokenize, _obj_0.TOKEN_TYPES
end
local tok_types
tok_types = function(src)
  local _accum_0 = { }
  local _len_0 = 1
  local _list_0 = tokenize(src)
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    _accum_0[_len_0] = t.type
    _len_0 = _len_0 + 1
  end
  return _accum_0
end
local tok_values
tok_values = function(src)
  local _accum_0 = { }
  local _len_0 = 1
  local _list_0 = tokenize(src)
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    _accum_0[_len_0] = t.value
    _len_0 = _len_0 + 1
  end
  return _accum_0
end
local first
first = function(src)
  return tokenize(src)[1]
end
R.describe("Lexer — tokens de base", function()
  R.it("source vide → un seul EOF", function()
    local tokens = tokenize("")
    R.eq(#tokens, 1)
    return R.eq(tokens[1].type, 'EOF')
  end)
  R.it("identifiant simple", function()
    local t = first("hello")
    R.eq(t.type, 'NAME')
    return R.eq(t.value, 'hello')
  end)
  R.it("mot-clé query est un NAME", function()
    R.eq(first("query").type, 'NAME')
    return R.eq(first("query").value, 'query')
  end)
  R.it("mot-clé mutation est un NAME", function()
    return R.eq(first("mutation").value, 'mutation')
  end)
  return R.it("underscore dans l'identifiant", function()
    local t = first("_my_field")
    R.eq(t.type, 'NAME')
    return R.eq(t.value, '_my_field')
  end)
end)
R.describe("Lexer — ponctuation", function()
  local cases = {
    {
      '!',
      'BANG'
    },
    {
      '$',
      'DOLLAR'
    },
    {
      '(',
      'PAREN_L'
    },
    {
      ')',
      'PAREN_R'
    },
    {
      '[',
      'BRACKET_L'
    },
    {
      ']',
      'BRACKET_R'
    },
    {
      '{',
      'BRACE_L'
    },
    {
      '}',
      'BRACE_R'
    },
    {
      ':',
      'COLON'
    },
    {
      '=',
      'EQUALS'
    },
    {
      '@',
      'AT'
    },
    {
      '|',
      'PIPE'
    },
    {
      '&',
      'AMP'
    },
    {
      '...',
      'SPREAD'
    }
  }
  for _, c in ipairs(cases) do
    local char = c[1]
    local expected_type = c[2]
    R.it(tostring(char) .. " → " .. tostring(expected_type), function()
      return R.eq((first(char)).type, expected_type)
    end)
  end
end)
R.describe("Lexer — nombres", function()
  R.it("entier positif", function()
    local t = first("42")
    R.eq(t.type, 'INT')
    return R.eq(t.value, '42')
  end)
  R.it("entier négatif", function()
    local t = first("-7")
    R.eq(t.type, 'INT')
    return R.eq(t.value, '-7')
  end)
  R.it("zéro", function()
    local t = first("0")
    R.eq(t.type, 'INT')
    return R.eq(t.value, '0')
  end)
  R.it("flottant", function()
    local t = first("3.14")
    R.eq(t.type, 'FLOAT')
    return R.eq(t.value, '3.14')
  end)
  R.it("flottant négatif", function()
    local t = first("-0.5")
    return R.eq(t.type, 'FLOAT')
  end)
  R.it("notation scientifique", function()
    local t = first("1e10")
    return R.eq(t.type, 'FLOAT')
  end)
  return R.it("notation scientifique avec exposant négatif", function()
    local t = first("1.5E-3")
    return R.eq(t.type, 'FLOAT')
  end)
end)
R.describe("Lexer — chaînes", function()
  R.it("chaîne simple", function()
    local t = first('"hello"')
    R.eq(t.type, 'STRING')
    return R.eq(t.value, 'hello')
  end)
  R.it("chaîne vide", function()
    local t = first('""')
    R.eq(t.type, 'STRING')
    return R.eq(t.value, '')
  end)
  R.it("chaîne avec échappement \\n", function()
    local t = first('"a\\nb"')
    R.eq(t.type, 'STRING')
    return R.matches(t.value, 'a')
  end)
  R.it("chaîne avec échappement \\t", function()
    local t = first('"a\\tb"')
    return R.eq(t.type, 'STRING')
  end)
  return R.it("block string (triple guillemets)", function()
    local t = first('"""hello world"""')
    R.eq(t.type, 'BLOCK_STRING')
    return R.matches(t.value, 'hello')
  end)
end)
R.describe("Lexer — espaces et commentaires", function()
  R.it("les espaces sont ignorés", function()
    local tokens = tokenize("   hello   ")
    R.eq(tokens[1].type, 'NAME')
    return R.eq(tokens[1].value, 'hello')
  end)
  R.it("les virgules sont ignorées", function()
    local types = tok_types("a, b, c")
    R.eq(types[1], 'NAME')
    R.eq(types[2], 'NAME')
    R.eq(types[3], 'NAME')
    return R.eq(types[4], 'EOF')
  end)
  R.it("les commentaires # sont ignorés", function()
    local tokens = tokenize("# commentaire\nhello")
    R.eq(tokens[1].type, 'NAME')
    return R.eq(tokens[1].value, 'hello')
  end)
  return R.it("les sauts de ligne sont ignorés", function()
    local tokens = tokenize("a\nb\nc")
    return R.eq(#tokens, 4)
  end)
end)
return R.describe("Lexer — séquences mixtes", function()
  R.it("requête minimaliste { field }", function()
    local types = tok_types("{ field }")
    R.eq(types[1], 'BRACE_L')
    R.eq(types[2], 'NAME')
    R.eq(types[3], 'BRACE_R')
    return R.eq(types[4], 'EOF')
  end)
  R.it("champ avec argument (arg: 123)", function()
    local types = tok_types("field(arg: 123)")
    R.eq(types[1], 'NAME')
    R.eq(types[2], 'PAREN_L')
    R.eq(types[3], 'NAME')
    R.eq(types[4], 'COLON')
    R.eq(types[5], 'INT')
    return R.eq(types[6], 'PAREN_R')
  end)
  R.it("type non-nul String!", function()
    local types = tok_types("String!")
    R.eq(types[1], 'NAME')
    return R.eq(types[2], 'BANG')
  end)
  R.it("liste [String]", function()
    local types = tok_types("[String]")
    R.eq(types[1], 'BRACKET_L')
    R.eq(types[2], 'NAME')
    return R.eq(types[3], 'BRACKET_R')
  end)
  R.it("variable $var", function()
    local types = tok_types("$var")
    R.eq(types[1], 'DOLLAR')
    return R.eq(types[2], 'NAME')
  end)
  return R.it("spread ...", function()
    local t = first("...")
    return R.eq(t.type, 'SPREAD')
  end)
end)
