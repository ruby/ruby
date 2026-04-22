h = {}
keys = Array.new(256) { |i| i }
keys.each { |k| h[k] = k }
20_000.times { keys.each { |k| h[k] } }
