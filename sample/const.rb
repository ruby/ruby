%test1 = 1
%test2 = 2

module Const
  %test3 = 3
  %test4 = 4
end

module Const2
  %test3 = 6
  %test4 = 8
end

include Const

print(%test1,%test2,%test3,%test4,"\n")

include Const2

print(%test1,%test2,%test3,%test4,"\n")
