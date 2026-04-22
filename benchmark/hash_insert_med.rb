keys = Array.new(256) { |i| "k#{i}".freeze }
30_000.times do
  h = {}
  keys.each { |k| h[k] = k }
end
