h = {}

10000.times do |i|
  h[i] = nil
end

500000.times do |i|
  [i].map(&h)
end
