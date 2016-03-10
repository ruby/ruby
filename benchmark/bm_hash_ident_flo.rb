h = {}.compare_by_identity
strs = (1..10000).to_a.map!(&:to_f)
strs.each { |s| h[s] = s }
50.times { strs.each { |s| h[s] } }
