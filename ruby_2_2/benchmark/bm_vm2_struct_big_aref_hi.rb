s = Struct.new(*('a'..'z').map { |x| x.to_sym })
x = s.new
i = 0
while i<6_000_000 # benchmark loop 2
  i += 1
  x.z # x[25]
end
