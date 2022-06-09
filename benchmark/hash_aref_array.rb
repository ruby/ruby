h = {}
arrays = (0..99).each_slice(10).to_a
#STDERR.puts arrays.inspect
arrays.each { |s| h[s] = s }
200_000.times { arrays.each { |s| h[s] } }
