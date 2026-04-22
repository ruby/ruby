h = {}
keys = Array.new(256) { |i| "k#{i}".to_sym }
keys.each { |k| h[k] = k }
20_000.times { keys.each { |k| h[k] } }
