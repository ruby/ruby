h = {}

(0xffff4000..0xffffffff).each do |i|
  h[i] = nil
end

300000.times do
  k, v = h.shift
  h[k] = v
end
