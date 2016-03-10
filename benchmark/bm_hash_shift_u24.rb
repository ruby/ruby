h = {}

(0xff4000..0xffffff).each do |i|
  h[i] = nil
end

1000000.times do
  k, v = h.shift
  h[k] = v
end
