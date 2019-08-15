h = {}
syms = ('a'..'z').to_a
begin
  syms = eval("%i[#{syms.join(' ')}]")
rescue SyntaxError # <= 1.9.3
  syms.map!(&:to_sym)
end
syms.each { |s| h[s] = s }
200_000.times { syms.each { |s| h[s] } }
