h = {}
keys = Array.new(16_384) { |i| "k#{i}".to_sym }
keys.each { |k| h[k] = k }
500.times { keys.each { |k| h[k] } }
