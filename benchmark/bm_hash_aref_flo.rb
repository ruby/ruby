h = {}
strs = [*1..10000].map! {|i| i.fdiv(10)}
strs.each { |s| h[s] = s }
500.times { strs.each { |s| h[s] } }
