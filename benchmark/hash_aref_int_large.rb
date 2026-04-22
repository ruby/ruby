h = {}
keys = Array.new(16_384) { |i| i }
keys.each { |k| h[k] = k }
500.times { keys.each { |k| h[k] } }
