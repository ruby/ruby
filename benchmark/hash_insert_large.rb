keys = Array.new(16_384) { |i| "k#{i}".freeze }
500.times do
  h = {}
  keys.each { |k| h[k] = k }
end
