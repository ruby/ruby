h = {}
keys = Array.new(512) { |i| "k#{i}".freeze }
keys[0, 256].each { |k| h[k] = k }

i = 0
2_000_000.times do
  inkey = keys[i & 511]
  outkey = keys[(i - 256) & 511]
  h[inkey] = inkey
  h.delete(outkey)
  i += 1
end
