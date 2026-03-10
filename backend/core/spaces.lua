local log = require('log')
local validate_input
validate_input = require('core.config').validate_input
local FIELD_TYPES = {
  'String',
  'Int',
  'Float',
  'Boolean',
  'ID',
  'UUID',
  'Sequence',
  'Any',
  'Map',
  'Array',
  'Datetime'
}
local FIELD_TYPES_SET
do
  local _tbl_0 = { }
  for _index_0 = 1, #FIELD_TYPES do
    local v = FIELD_TYPES[_index_0]
    _tbl_0[v] = true
  end
  FIELD_TYPES_SET = _tbl_0
end
local SYSTEM_SPACES = {
  _tdb_spaces = {
    format = {
      {
        name = 'id',
        type = 'string'
      },
      {
        name = 'name',
        type = 'string'
      },
      {
        name = 'description',
        type = 'string'
      },
      {
        name = 'created_at',
        type = 'number'
      },
      {
        name = 'updated_at',
        type = 'number'
      }
    },
    indexes = {
      primary = {
        parts = {
          'id'
        },
        unique = true,
        type = 'HASH'
      },
      by_name = {
        parts = {
          'name'
        },
        unique = true,
        type = 'TREE'
      }
    }
  },
  _tdb_fields = {
    format = {
      {
        name = 'id',
        type = 'string'
      },
      {
        name = 'space_id',
        type = 'string'
      },
      {
        name = 'name',
        type = 'string'
      },
      {
        name = 'field_type',
        type = 'string'
      },
      {
        name = 'not_null',
        type = 'boolean'
      },
      {
        name = 'position',
        type = 'number'
      },
      {
        name = 'description',
        type = 'string'
      }
    },
    indexes = {
      primary = {
        parts = {
          'id'
        },
        unique = true,
        type = 'HASH'
      },
      by_space = {
        parts = {
          'space_id'
        },
        unique = false,
        type = 'TREE'
      },
      by_space_pos = {
        parts = {
          'space_id',
          'position'
        },
        unique = true,
        type = 'TREE'
      }
    }
  },
  _tdb_views = {
    format = {
      {
        name = 'id',
        type = 'string'
      },
      {
        name = 'space_id',
        type = 'string'
      },
      {
        name = 'name',
        type = 'string'
      },
      {
        name = 'view_type',
        type = 'string'
      },
      {
        name = 'config',
        type = 'string'
      },
      {
        name = 'created_at',
        type = 'number'
      },
      {
        name = 'updated_at',
        type = 'number'
      }
    },
    indexes = {
      primary = {
        parts = {
          'id'
        },
        unique = true,
        type = 'HASH'
      },
      by_space = {
        parts = {
          'space_id'
        },
        unique = false,
        type = 'TREE'
      },
      by_name = {
        parts = {
          'name'
        },
        unique = true,
        type = 'TREE'
      }
    }
  },
  _tdb_custom_views = {
    format = {
      {
        name = 'id',
        type = 'string'
      },
      {
        name = 'name',
        type = 'string'
      },
      {
        name = 'description',
        type = 'string'
      },
      {
        name = 'yaml',
        type = 'string'
      },
      {
        name = 'created_at',
        type = 'number'
      },
      {
        name = 'updated_at',
        type = 'number'
      }
    },
    indexes = {
      primary = {
        parts = {
          'id'
        },
        unique = true,
        type = 'HASH'
      },
      by_name = {
        parts = {
          'name'
        },
        unique = true,
        type = 'TREE'
      }
    }
  },
  _tdb_relations = {
    format = {
      {
        name = 'id',
        type = 'string'
      },
      {
        name = 'from_space_id',
        type = 'string'
      },
      {
        name = 'from_field_id',
        type = 'string'
      },
      {
        name = 'to_space_id',
        type = 'string'
      },
      {
        name = 'to_field_id',
        type = 'string'
      },
      {
        name = 'name',
        type = 'string'
      },
      {
        name = 'repr_formula',
        type = 'string',
        is_nullable = true
      }
    },
    indexes = {
      primary = {
        parts = {
          'id'
        },
        unique = true,
        type = 'HASH'
      },
      by_from = {
        parts = {
          'from_space_id'
        },
        unique = false,
        type = 'TREE'
      },
      by_to = {
        parts = {
          'to_space_id'
        },
        unique = false,
        type = 'TREE'
      }
    }
  },
  _tdb_users = {
    format = {
      {
        name = 'id',
        type = 'string'
      },
      {
        name = 'username',
        type = 'string'
      },
      {
        name = 'email',
        type = 'string'
      },
      {
        name = 'password_hash',
        type = 'string'
      },
      {
        name = 'salt',
        type = 'string'
      },
      {
        name = 'created_at',
        type = 'number'
      },
      {
        name = 'updated_at',
        type = 'number'
      }
    },
    indexes = {
      primary = {
        parts = {
          'id'
        },
        unique = true,
        type = 'HASH'
      },
      by_username = {
        parts = {
          'username'
        },
        unique = true,
        type = 'TREE'
      },
      by_email = {
        parts = {
          'email'
        },
        unique = true,
        type = 'TREE'
      }
    }
  },
  _tdb_groups = {
    format = {
      {
        name = 'id',
        type = 'string'
      },
      {
        name = 'name',
        type = 'string'
      },
      {
        name = 'description',
        type = 'string'
      },
      {
        name = 'created_at',
        type = 'number'
      }
    },
    indexes = {
      primary = {
        parts = {
          'id'
        },
        unique = true,
        type = 'HASH'
      },
      by_name = {
        parts = {
          'name'
        },
        unique = true,
        type = 'TREE'
      }
    }
  },
  _tdb_memberships = {
    format = {
      {
        name = 'user_id',
        type = 'string'
      },
      {
        name = 'group_id',
        type = 'string'
      }
    },
    indexes = {
      primary = {
        parts = {
          'user_id',
          'group_id'
        },
        unique = true,
        type = 'HASH'
      },
      by_user = {
        parts = {
          'user_id'
        },
        unique = false,
        type = 'TREE'
      },
      by_group = {
        parts = {
          'group_id'
        },
        unique = false,
        type = 'TREE'
      }
    }
  },
  _tdb_permissions = {
    format = {
      {
        name = 'id',
        type = 'string'
      },
      {
        name = 'group_id',
        type = 'string'
      },
      {
        name = 'resource_type',
        type = 'string'
      },
      {
        name = 'resource_id',
        type = 'string'
      },
      {
        name = 'level',
        type = 'string'
      }
    },
    indexes = {
      primary = {
        parts = {
          'id'
        },
        unique = true,
        type = 'HASH'
      },
      by_group = {
        parts = {
          'group_id'
        },
        unique = false,
        type = 'TREE'
      },
      by_resource = {
        parts = {
          'resource_type',
          'resource_id'
        },
        unique = false,
        type = 'TREE'
      }
    }
  },
  _tdb_sessions = {
    format = {
      {
        name = 'token',
        type = 'string'
      },
      {
        name = 'user_id',
        type = 'string'
      },
      {
        name = 'created_at',
        type = 'number'
      },
      {
        name = 'expires_at',
        type = 'number'
      }
    },
    indexes = {
      primary = {
        parts = {
          'token'
        },
        unique = true,
        type = 'HASH'
      },
      by_user = {
        parts = {
          'user_id'
        },
        unique = false,
        type = 'TREE'
      }
    }
  }
}
local create_space
create_space = function(name, desc)
  if box.space[name] then
    return 
  end
  local s = box.schema.space.create(name, {
    format = desc.format,
    if_not_exists = true
  })
  if desc.indexes.primary then
    local opts = {
      parts = desc.indexes.primary.parts,
      unique = desc.indexes.primary.unique,
      type = desc.indexes.primary.type,
      if_not_exists = true
    }
    s:create_index('primary', opts)
  end
  for idx_name, idx_def in pairs(desc.indexes) do
    local _continue_0 = false
    repeat
      if idx_name == 'primary' then
        _continue_0 = true
        break
      end
      local opts = {
        parts = idx_def.parts,
        unique = idx_def.unique,
        type = idx_def.type,
        if_not_exists = true
      }
      s:create_index(idx_name, opts)
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  return log.info("Created space: " .. tostring(name))
end
local bootstrap
bootstrap = function()
  box.once('tdb_v1', function()
    log.info('Bootstrapping tdb system spaces…')
    for name, desc in pairs(SYSTEM_SPACES) do
      create_space(name, desc)
    end
    local admin_gid = require('uuid').new()
    box.space._tdb_groups:insert({
      tostring(admin_gid),
      'admin',
      'Administrators with full access',
      os.time()
    })
    local auth_mod = require('core.auth')
    local admin_user = os.getenv('TDB_ADMIN_USER') or 'admin'
    local admin_pass = os.getenv('TDB_ADMIN_PASSWORD') or 'admin'
    local u = auth_mod.create_user(admin_user, '', admin_pass)
    box.space._tdb_memberships:insert({
      u.id,
      tostring(admin_gid)
    })
    return log.info("tdb bootstrap complete. Default admin: " .. tostring(admin_user))
  end)
  return box.once('tdb_v2', function()
    local sp = box.space._tdb_relations
    if sp then
      local new_fmt = {
        {
          name = 'id',
          type = 'string'
        },
        {
          name = 'from_space_id',
          type = 'string'
        },
        {
          name = 'from_field_id',
          type = 'string'
        },
        {
          name = 'to_space_id',
          type = 'string'
        },
        {
          name = 'to_field_id',
          type = 'string'
        },
        {
          name = 'name',
          type = 'string'
        },
        {
          name = 'repr_formula',
          type = 'string',
          is_nullable = true
        }
      }
      sp:format(new_fmt)
      return log.info('tdb_v2: added repr_formula to _tdb_relations')
    end
  end)
end
local create_user_space
create_user_space = function(name, description)
  local uuid = require('uuid')
  local now = os.time()
  local sid = tostring(uuid.new())
  local meta = {
    sid,
    name,
    description or '',
    now,
    now
  }
  box.space._tdb_spaces:insert(meta)
  box.schema.space.create("data_" .. tostring(name), {
    if_not_exists = true
  })
  box.space["data_" .. tostring(name)]:create_index('primary', {
    parts = {
      1
    },
    type = 'HASH',
    if_not_exists = true
  })
  return {
    id = sid,
    name = name,
    description = description or '',
    createdAt = now,
    updatedAt = now
  }
end
local add_field
add_field = function(space_id, field_name, field_type, not_null, description, formula, trigger_fields, language, repr_formula)
  local uuid = require('uuid')
  local json = require('json')
  if not (FIELD_TYPES_SET[field_type]) then
    error("Type de champ invalide : " .. tostring(field_type))
  end
  if not (validate_input('field_name', field_name, "add_field")) then
    error("Field name too long: " .. tostring(#field_name) .. " chars")
  end
  if formula and not validate_input('formula', formula, "add_field") then
    error("Formula too long: " .. tostring(#formula) .. " chars")
  end
  if repr_formula and not validate_input('formula', repr_formula, "add_field") then
    error("Representation formula too long: " .. tostring(#repr_formula) .. " chars")
  end
  local pos = 1
  local _list_0 = box.space._tdb_fields.index.by_space:select({
    space_id
  })
  for _index_0 = 1, #_list_0 do
    local _ = _list_0[_index_0]
    pos = pos + 1
  end
  local fid = tostring(uuid.new())
  local tuple = {
    fid,
    space_id,
    field_name,
    field_type,
    not_null or false,
    pos,
    description or ''
  }
  if formula and formula ~= '' then
    table.insert(tuple, formula)
    table.insert(tuple, json.encode(trigger_fields))
    table.insert(tuple, language or 'lua')
    table.insert(tuple, repr_formula or '')
  elseif repr_formula and repr_formula ~= '' then
    table.insert(tuple, '')
    table.insert(tuple, json.encode(nil))
    table.insert(tuple, 'lua')
    table.insert(tuple, repr_formula)
  end
  box.space._tdb_fields:insert(tuple)
  if field_type == 'Sequence' then
    box.schema.sequence.create("_tdb_seq_" .. tostring(fid), {
      start = 1,
      min = 1,
      step = 1,
      if_not_exists = true
    })
    local seq = box.sequence["_tdb_seq_" .. tostring(fid)]
    local space_meta = box.space._tdb_spaces:get(space_id)
    if space_meta and seq then
      local data_sp = box.space["data_" .. tostring(space_meta[2])]
      if data_sp then
        local _list_1 = data_sp:select({ })
        for _index_0 = 1, #_list_1 do
          local t = _list_1[_index_0]
          local d
          if type(t[2]) == 'string' then
            d = require('json').decode(t[2])
          else
            d = t[2]
          end
          d[field_name] = seq:next()
          data_sp:replace({
            t[1],
            require('json').encode(d)
          })
        end
      end
    end
  end
  return {
    id = fid,
    spaceId = space_id,
    name = field_name,
    fieldType = field_type,
    notNull = not_null or false,
    position = pos,
    description = description or '',
    formula = formula or '',
    triggerFields = trigger_fields,
    language = language or 'lua',
    reprFormula = repr_formula or ''
  }
end
local remove_field
remove_field = function(field_id)
  local t = box.space._tdb_fields:get(field_id)
  if t and t[4] == 'Sequence' then
    local seq = box.sequence["_tdb_seq_" .. tostring(field_id)]
    if seq then
      seq:drop()
    end
  end
  box.space._tdb_fields:delete(field_id)
  return true
end
local list_spaces
list_spaces = function()
  local result = { }
  local _list_0 = box.space._tdb_spaces:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    table.insert(result, {
      id = t[1],
      name = t[2],
      description = t[3],
      createdAt = t[4],
      updatedAt = t[5]
    })
  end
  return result
end
local get_space
get_space = function(id)
  local t = box.space._tdb_spaces:get(id)
  if not (t) then
    return nil
  end
  return {
    id = t[1],
    name = t[2],
    description = t[3],
    createdAt = t[4],
    updatedAt = t[5]
  }
end
local get_space_by_name
get_space_by_name = function(name)
  local t = box.space._tdb_spaces.index.by_name:get(name)
  if not (t) then
    return nil
  end
  return {
    id = t[1],
    name = t[2],
    description = t[3],
    createdAt = t[4],
    updatedAt = t[5]
  }
end
local list_fields
list_fields = function(space_id)
  local result = { }
  local json = require('json')
  local _list_0 = box.space._tdb_fields.index.by_space_pos:select({
    space_id
  })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    local trigger_raw = t[9]
    local trigger_fields
    if trigger_raw and trigger_raw ~= 'null' then
      trigger_fields = json.decode(trigger_raw)
    else
      trigger_fields = nil
    end
    table.insert(result, {
      id = t[1],
      spaceId = t[2],
      name = t[3],
      fieldType = t[4],
      notNull = t[5],
      position = t[6],
      description = t[7],
      formula = t[8] or '',
      triggerFields = trigger_fields,
      language = t[10] or 'lua',
      reprFormula = t[11] or ''
    })
  end
  return result
end
local update_field
update_field = function(field_id, opts)
  local json = require('json')
  local t = box.space._tdb_fields:get(field_id)
  if not (t) then
    error("Field not found: " .. tostring(field_id))
  end
  if opts.name and not validate_input('field_name', opts.name, "update_field") then
    error("Field name too long: " .. tostring(#opts.name) .. " chars")
  end
  if opts.formula and not validate_input('formula', opts.formula, "update_field") then
    error("Formula too long: " .. tostring(#opts.formula) .. " chars")
  end
  if opts.reprFormula and not validate_input('formula', opts.reprFormula, "update_field") then
    error("Representation formula too long: " .. tostring(#opts.reprFormula) .. " chars")
  end
  local name = opts.name or t[3]
  local not_null
  if opts.notNull ~= nil then
    not_null = opts.notNull
  else
    not_null = t[5]
  end
  local desc = opts.description or t[7]
  local formula = opts.formula
  local trigger_fields = opts.triggerFields
  local language = opts.language or t[10] or 'lua'
  local repr_formula
  if opts.reprFormula ~= nil then
    repr_formula = opts.reprFormula
  else
    repr_formula = (t[11] or '')
  end
  local tuple = {
    t[1],
    t[2],
    name,
    t[4],
    not_null,
    t[6],
    desc
  }
  if (formula and formula ~= '') or (repr_formula and repr_formula ~= '') then
    local actual_formula
    if formula ~= nil then
      actual_formula = formula
    else
      actual_formula = (t[8] or '')
    end
    local actual_trigger
    if opts.formula ~= nil then
      actual_trigger = trigger_fields
    else
      do
        local raw = t[9]
        if raw and raw ~= 'null' then
          actual_trigger = json.decode(raw)
        else
          actual_trigger = nil
        end
      end
    end
    table.insert(tuple, actual_formula)
    table.insert(tuple, json.encode(actual_trigger))
    table.insert(tuple, language)
    table.insert(tuple, repr_formula)
  elseif formula == '' then
    table.insert(tuple, '')
    table.insert(tuple, json.encode(nil))
    table.insert(tuple, language)
    table.insert(tuple, repr_formula)
  end
  box.space._tdb_fields:replace(tuple)
  local trigger_raw
  if #tuple >= 9 then
    trigger_raw = tuple[9]
  else
    trigger_raw = nil
  end
  local tf
  if trigger_raw and trigger_raw ~= 'null' then
    tf = json.decode(trigger_raw)
  else
    tf = nil
  end
  return {
    id = t[1],
    spaceId = t[2],
    name = name,
    fieldType = t[4],
    notNull = not_null,
    position = t[6],
    description = desc,
    formula = ((function()
      if #tuple >= 8 then
        return tuple[8]
      else
        return ''
      end
    end)()) or '',
    triggerFields = tf,
    language = language,
    reprFormula = repr_formula
  }
end
local reorder_fields
reorder_fields = function(space_id, field_ids)
  for pos, fid in ipairs(field_ids) do
    local _continue_0 = false
    repeat
      local t = box.space._tdb_fields:get(fid)
      if not (t and t[2] == space_id) then
        _continue_0 = true
        break
      end
      box.space._tdb_fields:update(fid, {
        {
          '=',
          6,
          10000 + pos
        }
      })
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  for pos, fid in ipairs(field_ids) do
    local _continue_0 = false
    repeat
      local t = box.space._tdb_fields:get(fid)
      if not (t and t[2] == space_id) then
        _continue_0 = true
        break
      end
      box.space._tdb_fields:update(fid, {
        {
          '=',
          6,
          pos
        }
      })
      _continue_0 = true
    until true
    if not _continue_0 then
      break
    end
  end
  return list_fields(space_id)
end
local change_field_type
change_field_type = function(field_id, new_type, conversion_formula, language)
  local json = require('json')
  local t = box.space._tdb_fields:get(field_id)
  if not (t) then
    error("Field not found: " .. tostring(field_id))
  end
  if not (FIELD_TYPES_SET[new_type]) then
    error("Type de champ invalide : " .. tostring(new_type))
  end
  local field_name = t[3]
  local space_id = t[2]
  local space_meta = box.space._tdb_spaces:get(space_id)
  if not (space_meta) then
    error("Space not found")
  end
  local space_name = space_meta[2]
  if conversion_formula and conversion_formula ~= '' then
    local lang = language or 'lua'
    local lua_chunk
    if lang == 'moonscript' then
      local ok_ms, moon = pcall(require, 'moonscript.base')
      if not (ok_ms) then
        error("MoonScript non disponible: " .. tostring(moon))
      end
      local moon_src = "return (self, space) -> " .. conversion_formula
      local ok_c, lua_or_err = pcall(moon.to_lua, moon_src)
      if not (ok_c) then
        error("MoonScript parse error: " .. tostring(lua_or_err))
      end
      lua_chunk = lua_or_err
    else
      lua_chunk = "return function(self, space) return " .. conversion_formula .. " end"
    end
    local chunk_fn, load_err = load(lua_chunk)
    if not (chunk_fn) then
      error("Parse error: " .. tostring(load_err))
    end
    local ok2, conv_fn = pcall(chunk_fn)
    if not (ok2 and type(conv_fn) == 'function') then
      error("Compilation error: " .. tostring(conv_fn))
    end
    local data_sp = box.space["data_" .. tostring(space_name)]
    if data_sp then
      local _list_0 = data_sp:select({ })
      for _index_0 = 1, #_list_0 do
        local raw_t = _list_0[_index_0]
        local d
        if type(raw_t[2]) == 'string' then
          d = json.decode(raw_t[2])
        else
          d = raw_t[2]
        end
        local ok_r, new_val = pcall(conv_fn, d, nil)
        if ok_r then
          d[field_name] = new_val
        end
        data_sp:replace({
          raw_t[1],
          json.encode(d)
        })
      end
    end
  end
  local new_tuple = {
    t[1],
    t[2],
    t[3],
    new_type,
    t[5],
    t[6],
    t[7]
  }
  if t[8] ~= nil then
    table.insert(new_tuple, t[8])
    table.insert(new_tuple, t[9])
    table.insert(new_tuple, t[10])
    table.insert(new_tuple, t[11])
  end
  box.space._tdb_fields:replace(new_tuple)
  local trigger_raw = t[9]
  local tf
  if trigger_raw and trigger_raw ~= 'null' then
    tf = json.decode(trigger_raw)
  else
    tf = nil
  end
  return {
    id = t[1],
    spaceId = t[2],
    name = t[3],
    fieldType = new_type,
    notNull = t[5],
    position = t[6],
    description = t[7],
    formula = t[8] or '',
    triggerFields = tf,
    language = t[10] or 'lua',
    reprFormula = t[11] or ''
  }
end
local migrate
migrate = function()
  for name, desc in pairs(SYSTEM_SPACES) do
    create_space(name, desc)
  end
  local _list_0 = box.space._tdb_fields:select({ })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    if t[4] == 'Sequence' then
      local seq_name = "_tdb_seq_" .. tostring(t[1])
      if not (box.sequence[seq_name]) then
        box.schema.sequence.create(seq_name, {
          start = 1,
          min = 1,
          step = 1
        })
        log.info("Created missing sequence: " .. tostring(seq_name))
      end
    end
  end
end
local delete_user_space
delete_user_space = function(name)
  if not (name) then
    return 
  end
  local meta = box.space._tdb_spaces.index.by_name:get(name)
  if not (meta) then
    return 
  end
  local sid = meta[1]
  local trg_mod = package.loaded['core.triggers']
  if trg_mod and trg_mod.deregister_space_trigger then
    pcall(trg_mod.deregister_space_trigger, name)
  end
  local _list_0 = box.space._tdb_fields.index.by_space:select({
    sid
  })
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    if t[4] == 'Sequence' then
      local seq = box.sequence["_tdb_seq_" .. tostring(t[1])]
      if seq then
        seq:drop()
      end
    end
    box.space._tdb_fields:delete(t[1])
  end
  local sp = box.space["data_" .. tostring(name)]
  if sp then
    sp:drop()
  end
  return box.space._tdb_spaces:delete(sid)
end
return {
  bootstrap = bootstrap,
  migrate = migrate,
  create_user_space = create_user_space,
  delete_user_space = delete_user_space,
  add_field = add_field,
  remove_field = remove_field,
  update_field = update_field,
  reorder_fields = reorder_fields,
  change_field_type = change_field_type,
  list_spaces = list_spaces,
  list_fields = list_fields,
  get_space = get_space,
  get_space_by_name = get_space_by_name,
  FIELD_TYPES = FIELD_TYPES
}
