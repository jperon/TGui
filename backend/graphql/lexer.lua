local TOKEN_TYPES = {
  SOF = 'SOF',
  EOF = 'EOF',
  BANG = 'BANG',
  DOLLAR = 'DOLLAR',
  PAREN_L = 'PAREN_L',
  PAREN_R = 'PAREN_R',
  SPREAD = 'SPREAD',
  COLON = 'COLON',
  EQUALS = 'EQUALS',
  AT = 'AT',
  BRACKET_L = 'BRACKET_L',
  BRACKET_R = 'BRACKET_R',
  BRACE_L = 'BRACE_L',
  PIPE = 'PIPE',
  BRACE_R = 'BRACE_R',
  AMP = 'AMP',
  NAME = 'NAME',
  INT = 'INT',
  FLOAT = 'FLOAT',
  STRING = 'STRING',
  BLOCK_STRING = 'BLOCK_STRING',
  COMMENT = 'COMMENT'
}
local is_name_start
is_name_start = function(c)
  return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_'
end
local is_digit
is_digit = function(c)
  return c >= '0' and c <= '9'
end
local is_name_continue
is_name_continue = function(c)
  return is_name_start(c) or is_digit(c)
end
local Lexer
do
  local _class_0
  local _base_0 = {
    peek = function(self, offset)
      if offset == nil then
        offset = 0
      end
      local p = self.pos + offset
      if p > self.len then
        return ''
      end
      return self.source:sub(p, p)
    end,
    advance = function(self, n)
      if n == nil then
        n = 1
      end
      self.pos = self.pos + n
    end,
    skip_ignored = function(self)
      while self.pos <= self.len do
        local c = self:peek()
        if c == ' ' or c == '\t' or c == '\r' or c == '\n' or c == ',' then
          self:advance()
        elseif c == '#' then
          while self.pos <= self.len and self:peek() ~= '\n' do
            self:advance()
          end
        else
          break
        end
      end
    end,
    read_string = function(self)
      if self.source:sub(self.pos, self.pos + 2) == '"""' then
        return self:read_block_string()
      end
      self:advance()
      local start = self.pos
      local buf = { }
      while self.pos <= self.len do
        local c = self:peek()
        if c == '"' then
          self:advance()
          return table.concat(buf), TOKEN_TYPES.STRING
        elseif c == '\\' then
          self:advance()
          local esc = self:peek()
          self:advance()
          local escaped
          local _exp_0 = esc
          if '"' == _exp_0 then
            escaped = '"'
          elseif '\\' == _exp_0 then
            escaped = '\\'
          elseif '/' == _exp_0 then
            escaped = '/'
          elseif 'b' == _exp_0 then
            escaped = '\b'
          elseif 'f' == _exp_0 then
            escaped = '\f'
          elseif 'n' == _exp_0 then
            escaped = '\n'
          elseif 'r' == _exp_0 then
            escaped = '\r'
          elseif 't' == _exp_0 then
            escaped = '\t'
          elseif 'u' == _exp_0 then
            local hex = self.source:sub(self.pos, self.pos + 3)
            self:advance(4)
            escaped = string.char(tonumber(hex, 16))
          else
            escaped = error("Invalid escape \\" .. tostring(esc))
          end
          table.insert(buf, escaped)
        elseif c == '\n' or c == '\r' then
          error("Unterminated string")
        else
          table.insert(buf, c)
          self:advance()
        end
      end
      return error("Unterminated string")
    end,
    read_block_string = function(self)
      self:advance(3)
      local buf = { }
      while self.pos <= self.len do
        if self.source:sub(self.pos, self.pos + 2) == '"""' then
          self:advance(3)
          return table.concat(buf), TOKEN_TYPES.BLOCK_STRING
        end
        table.insert(buf, self:peek())
        self:advance()
      end
      return error("Unterminated block string")
    end,
    read_number = function(self)
      local start = self.pos
      local is_float = false
      if self:peek() == '-' then
        self:advance()
      end
      if self:peek() == '0' then
        self:advance()
      else
        while is_digit(self:peek()) do
          self:advance()
        end
      end
      if self:peek() == '.' then
        is_float = true
        self:advance()
        while is_digit(self:peek()) do
          self:advance()
        end
      end
      if self:peek() == 'e' or self:peek() == 'E' then
        is_float = true
        self:advance()
        if self:peek() == '+' or self:peek() == '-' then
          self:advance()
        end
        while is_digit(self:peek()) do
          self:advance()
        end
      end
      local raw = self.source:sub(start, self.pos - 1)
      if is_float then
        return raw, TOKEN_TYPES.FLOAT
      else
        return raw, TOKEN_TYPES.INT
      end
    end,
    next_token = function(self)
      local tok
      self:skip_ignored()
      if self.pos > self.len then
        return {
          type = TOKEN_TYPES.EOF,
          value = nil
        }
      end
      local c = self:peek()
      if c == '!' then
        self:advance()
        tok = {
          type = TOKEN_TYPES.BANG,
          value = '!'
        }
      elseif c == '$' then
        self:advance()
        tok = {
          type = TOKEN_TYPES.DOLLAR,
          value = '$'
        }
      elseif c == '(' then
        self:advance()
        tok = {
          type = TOKEN_TYPES.PAREN_L,
          value = '('
        }
      elseif c == ')' then
        self:advance()
        tok = {
          type = TOKEN_TYPES.PAREN_R,
          value = ')'
        }
      elseif c == '.' and self.source:sub(self.pos, self.pos + 2) == '...' then
        self:advance(3)
        tok = {
          type = TOKEN_TYPES.SPREAD,
          value = '...'
        }
      elseif c == ':' then
        self:advance()
        tok = {
          type = TOKEN_TYPES.COLON,
          value = ':'
        }
      elseif c == '=' then
        self:advance()
        tok = {
          type = TOKEN_TYPES.EQUALS,
          value = '='
        }
      elseif c == '@' then
        self:advance()
        tok = {
          type = TOKEN_TYPES.AT,
          value = '@'
        }
      elseif c == '[' then
        self:advance()
        tok = {
          type = TOKEN_TYPES.BRACKET_L,
          value = '['
        }
      elseif c == ']' then
        self:advance()
        tok = {
          type = TOKEN_TYPES.BRACKET_R,
          value = ']'
        }
      elseif c == '{' then
        self:advance()
        tok = {
          type = TOKEN_TYPES.BRACE_L,
          value = '{'
        }
      elseif c == '}' then
        self:advance()
        tok = {
          type = TOKEN_TYPES.BRACE_R,
          value = '}'
        }
      elseif c == '|' then
        self:advance()
        tok = {
          type = TOKEN_TYPES.PIPE,
          value = '|'
        }
      elseif c == '&' then
        self:advance()
        tok = {
          type = TOKEN_TYPES.AMP,
          value = '&'
        }
      elseif c == '"' then
        local val, typ = self:read_string()
        tok = {
          type = typ,
          value = val
        }
      elseif c == '-' or is_digit(c) then
        local val, typ = self:read_number()
        tok = {
          type = typ,
          value = val
        }
      elseif is_name_start(c) then
        local start = self.pos
        while is_name_continue(self:peek()) do
          self:advance()
        end
        local name = self.source:sub(start, self.pos - 1)
        tok = {
          type = TOKEN_TYPES.NAME,
          value = name
        }
      else
        error("Unexpected character: " .. tostring(c) .. " at position " .. tostring(self.pos))
      end
      return tok
    end,
    tokenize = function(self)
      local tokens = { }
      while true do
        local tok = self:next_token()
        table.insert(tokens, tok)
        if tok.type == TOKEN_TYPES.EOF then
          break
        end
      end
      return tokens
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, source)
      self.source = source
      self.pos = 1
      self.len = #source
      self.tokens = { }
      self.index = 0
    end,
    __base = _base_0,
    __name = "Lexer"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  Lexer = _class_0
end
local tokenize
tokenize = function(source)
  return Lexer(source):tokenize()
end
return {
  TOKEN_TYPES = TOKEN_TYPES,
  Lexer = Lexer,
  tokenize = tokenize
}
