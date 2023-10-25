i = 0
x = 0
y = 9
while i<6_000_000 # benchmark loop 2
  i += 1
  str = "foo#{x}bar#{y}baz"
end
