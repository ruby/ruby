h = {}.compare_by_identity
strs = ('a'..'z').to_a
strs.each { |s| h[s] = s }
500_000.times { strs.each { |s| h[s] } }
