i = 0
x = true
y = false
while i<6_000_000 # benchmark loop 2
  i += 1
  str = "foo#{x}bar#{y}baz"
end
