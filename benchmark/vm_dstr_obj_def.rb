i = 0
o = Object.new
def o.to_s; -""; end
x = y = o
while i<6_000_000 # benchmark loop 2
  i += 1
  str = "foo#{x}bar#{y}baz"
end
