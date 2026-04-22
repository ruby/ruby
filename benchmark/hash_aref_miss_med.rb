h = {}
present = Array.new(256) { |i| "k#{i}".freeze }
present.each { |k| h[k] = k }
missing = Array.new(256) { |i| "miss#{i}".freeze }
20_000.times { missing.each { |k| h[k] } }
