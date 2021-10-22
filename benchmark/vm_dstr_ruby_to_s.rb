# frozen_string_literal: true
i = 0
x = y = Object.new
def x.to_s
  '1'
end
while i<6_000_000 # benchmark loop 2
  i += 1
  str = "foo#{x}bar#{y}baz"
end
