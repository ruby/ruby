h = {}
keys = Array.new(16_384) { |i| "k#{i}".freeze }
keys.each { |k| h[k] = k }
500.times { keys.each { |k| h[k] } }
