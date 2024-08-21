require 'continuation'
cont = nil
a = [*1..10].reject do |i|
  callcc {|c| cont = c} if !cont and i == 10
  false
end
if a.size < 1000
  a.unshift(:x)
  cont.call
end
