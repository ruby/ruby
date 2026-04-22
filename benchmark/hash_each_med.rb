h = {}
Array.new(256) { |i| "k#{i}".freeze }.each { |k| h[k] = k }
20_000.times { h.each { |_k, _v| } }
