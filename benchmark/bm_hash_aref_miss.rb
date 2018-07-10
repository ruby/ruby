h = {}
strs = ('a'..'z').to_a.map!(&:freeze)
strs.each { |s| h[s] = s }
strs = ('A'..'Z').to_a
200_000.times { strs.each { |s| h[s] } }
