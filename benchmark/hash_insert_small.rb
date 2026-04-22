keys = Array.new(16) { |i| "k#{i}".freeze }
500_000.times do
  h = {}
  keys.each { |k| h[k] = k }
end
