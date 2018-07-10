h = {}
syms = %w[puts warn syswrite write stat bacon lettuce tomato
some symbols in this array may already be interned  others should not be
hash browns make good breakfast but not cooked using prime numbers
shift for division entries delete_if keys exist?
]
begin
  syms = eval("%i[#{syms.join(' ')}]")
rescue SyntaxError # <= 1.9.3
  syms.map!(&:to_sym)
end
syms.each { |s| h[s] = s }
200_000.times { syms.each { |s| h[s] } }
