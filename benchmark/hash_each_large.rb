h = {}
Array.new(16_384) { |i| "k#{i}".freeze }.each { |k| h[k] = k }
500.times { h.each { |_k, _v| } }
