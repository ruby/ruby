h = {}
present = Array.new(16_384) { |i| "k#{i}".freeze }
present.each { |k| h[k] = k }
missing = Array.new(16_384) { |i| "miss#{i}".freeze }
500.times { missing.each { |k| h[k] } }
