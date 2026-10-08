-- tools/seed_rng.moon — générateur pseudo-aléatoire déterministe (Park–Miller).
new = (seed) ->
  state = seed % 2147483647
  state = 1 if state <= 0
  step = ->
    state = (state * 48271) % 2147483647
    state
  rng = {}
  rng.int = (lo, hi) -> lo + step! % (hi - lo + 1)
  rng.pick = (list) -> list[rng.int 1, #list]
  rng.chance = (p) -> (step! % 1000) < p * 1000
  rng.shuffle = (list) ->
    out = [v for v in *list]
    for i = #out, 2, -1
      j = rng.int 1, i
      out[i], out[j] = out[j], out[i]
    out
  rng

{ :new }
