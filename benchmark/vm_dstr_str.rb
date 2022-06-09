i = 0
x = y = ""
while i<6_000_000 # benchmark loop 2
  i += 1
  str = "foo#{x}bar#{y}baz"
end
