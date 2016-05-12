s = Struct.new(:a, :b, :c)
x = s.new
i = 0
while i<6_000_000 # benchmark loop 2
  i += 1
  x[:a]
end
