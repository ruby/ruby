h = {}.compare_by_identity
syms = ('a'..'z').to_a.map(&:to_sym)
syms.each { |s| h[s] = s }
500_000.times { syms.each { |s| h[s] } }
