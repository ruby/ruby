ary = Array.new(1000) { rand(1000) }
10000.times { ary.sort { |a, b| a <=> b } }
