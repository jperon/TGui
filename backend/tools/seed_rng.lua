local new
new = function(seed)
  local state = seed % 2147483647
  if state <= 0 then
    state = 1
  end
  local step
  step = function()
    state = (state * 48271) % 2147483647
    return state
  end
  local rng = { }
  rng.int = function(lo, hi)
    return lo + step() % (hi - lo + 1)
  end
  rng.pick = function(list)
    return list[rng.int(1, #list)]
  end
  rng.chance = function(p)
    return (step() % 1000) < p * 1000
  end
  rng.shuffle = function(list)
    local out
    do
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #list do
        local v = list[_index_0]
        _accum_0[_len_0] = v
        _len_0 = _len_0 + 1
      end
      out = _accum_0
    end
    for i = #out, 2, -1 do
      local j = rng.int(1, i)
      out[i], out[j] = out[j], out[i]
    end
    return out
  end
  return rng
end
return {
  new = new
}
