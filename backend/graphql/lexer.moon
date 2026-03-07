-- graphql/lexer.moon
-- Tokenizes a GraphQL document (query or SDL) into a token stream.

TOKEN_TYPES =
  SOF:          'SOF'
  EOF:          'EOF'
  BANG:         'BANG'
  DOLLAR:       'DOLLAR'
  PAREN_L:      'PAREN_L'
  PAREN_R:      'PAREN_R'
  SPREAD:       'SPREAD'
  COLON:        'COLON'
  EQUALS:       'EQUALS'
  AT:           'AT'
  BRACKET_L:    'BRACKET_L'
  BRACKET_R:    'BRACKET_R'
  BRACE_L:      'BRACE_L'
  PIPE:         'PIPE'
  BRACE_R:      'BRACE_R'
  AMP:          'AMP'
  NAME:         'NAME'
  INT:          'INT'
  FLOAT:        'FLOAT'
  STRING:       'STRING'
  BLOCK_STRING: 'BLOCK_STRING'
  COMMENT:      'COMMENT'

-- Returns true if the character is a valid identifier start
is_name_start = (c) ->
  (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_'

is_digit = (c) ->
  c >= '0' and c <= '9'

is_name_continue = (c) ->
  is_name_start(c) or is_digit(c)

-- Lexer class
class Lexer
  new: (source) =>
    @source = source
    @pos    = 1
    @len    = #source
    @tokens = {}
    @index  = 0

  -- Peek at character at offset from current position (default 0)
  peek: (offset = 0) =>
    p = @pos + offset
    if p > @len then return ''
    @source\sub p, p

  advance: (n = 1) =>
    @pos += n

  -- Skip whitespace, commas (ignored in GQL), and comments
  skip_ignored: =>
    while @pos <= @len
      c = @peek!
      if c == ' ' or c == '\t' or c == '\r' or c == '\n' or c == ','
        @advance!
      elseif c == '#'
        -- skip line comment
        while @pos <= @len and @peek! != '\n'
          @advance!
      else
        break

  read_string: =>
    -- Check for block string
    if @source\sub(@pos, @pos + 2) == '"""'
      return @read_block_string!
    @advance! -- skip opening "
    start = @pos
    buf = {}
    while @pos <= @len
      c = @peek!
      if c == '"'
        @advance! -- skip closing "
        return table.concat(buf), TOKEN_TYPES.STRING
      elseif c == '\\'
        @advance!
        esc = @peek!
        @advance!
        escaped = switch esc
          when '"'  then '"'
          when '\\' then '\\'
          when '/'  then '/'
          when 'b'  then '\b'
          when 'f'  then '\f'
          when 'n'  then '\n'
          when 'r'  then '\r'
          when 't'  then '\t'
          when 'u'
            hex = @source\sub @pos, @pos + 3
            @advance 4
            string.char tonumber(hex, 16)
          else error "Invalid escape \\#{esc}"
        table.insert buf, escaped
      elseif c == '\n' or c == '\r'
        error "Unterminated string"
      else
        table.insert buf, c
        @advance!
    error "Unterminated string"

  read_block_string: =>
    @advance 3 -- skip """
    buf = {}
    while @pos <= @len
      if @source\sub(@pos, @pos + 2) == '"""'
        @advance 3
        -- Strip common leading whitespace (simplified)
        return table.concat(buf), TOKEN_TYPES.BLOCK_STRING
      table.insert buf, @peek!
      @advance!
    error "Unterminated block string"

  read_number: =>
    start = @pos
    is_float = false
    if @peek! == '-' then @advance!
    if @peek! == '0'
      @advance!
    else
      while is_digit @peek! do @advance!
    if @peek! == '.'
      is_float = true
      @advance!
      while is_digit @peek! do @advance!
    if @peek! == 'e' or @peek! == 'E'
      is_float = true
      @advance!
      if @peek! == '+' or @peek! == '-' then @advance!
      while is_digit @peek! do @advance!
    raw = @source\sub start, @pos - 1
    if is_float
      return raw, TOKEN_TYPES.FLOAT
    else
      return raw, TOKEN_TYPES.INT

  next_token: =>
    local tok
    @skip_ignored!
    if @pos > @len
      return { type: TOKEN_TYPES.EOF, value: nil }

    c = @peek!

    if c == '!'
      @advance!
      tok = { type: TOKEN_TYPES.BANG, value: '!' }
    elseif c == '$'
      @advance!
      tok = { type: TOKEN_TYPES.DOLLAR, value: '$' }
    elseif c == '('
      @advance!
      tok = { type: TOKEN_TYPES.PAREN_L, value: '(' }
    elseif c == ')'
      @advance!
      tok = { type: TOKEN_TYPES.PAREN_R, value: ')' }
    elseif c == '.' and @source\sub(@pos, @pos + 2) == '...'
      @advance 3
      tok = { type: TOKEN_TYPES.SPREAD, value: '...' }
    elseif c == ':'
      @advance!
      tok = { type: TOKEN_TYPES.COLON, value: ':' }
    elseif c == '='
      @advance!
      tok = { type: TOKEN_TYPES.EQUALS, value: '=' }
    elseif c == '@'
      @advance!
      tok = { type: TOKEN_TYPES.AT, value: '@' }
    elseif c == '['
      @advance!
      tok = { type: TOKEN_TYPES.BRACKET_L, value: '[' }
    elseif c == ']'
      @advance!
      tok = { type: TOKEN_TYPES.BRACKET_R, value: ']' }
    elseif c == '{'
      @advance!
      tok = { type: TOKEN_TYPES.BRACE_L, value: '{' }
    elseif c == '}'
      @advance!
      tok = { type: TOKEN_TYPES.BRACE_R, value: '}' }
    elseif c == '|'
      @advance!
      tok = { type: TOKEN_TYPES.PIPE, value: '|' }
    elseif c == '&'
      @advance!
      tok = { type: TOKEN_TYPES.AMP, value: '&' }
    elseif c == '"'
      val, typ = @read_string!
      tok = { type: typ, value: val }
    elseif c == '-' or is_digit c
      val, typ = @read_number!
      tok = { type: typ, value: val }
    elseif is_name_start c
      start = @pos
      while is_name_continue @peek! do @advance!
      name = @source\sub start, @pos - 1
      tok = { type: TOKEN_TYPES.NAME, value: name }
    else
      error "Unexpected character: #{c} at position #{@pos}"

    tok

  -- Tokenize the full source into a list
  tokenize: =>
    tokens = {}
    while true
      tok = @next_token!
      table.insert tokens, tok
      if tok.type == TOKEN_TYPES.EOF then break
    tokens

tokenize = (source) ->
  Lexer(source)\tokenize!

{ :TOKEN_TYPES, :Lexer, :tokenize }
