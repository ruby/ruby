h = {}
syms = %w[puts warn syswrite write stat bacon lettuce tomato
some symbols in this array may already be interned  others should not be
hash browns make good breakfast but not cooked using prime numbers
shift for division entries delete_if keys exist?
].map!(&:to_sym)
syms.each { |s| h[s] = s }
200_000.times { syms.each { |s| h[s] } }
