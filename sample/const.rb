# constant access test
# output:
#	1234
#	1268
TEST1 = 1
TEST2 = 2

module Const
  TEST3 = 3
  TEST4 = 4
end

module Const2
  TEST3 = 6
  TEST4 = 8
end

include Const

print(TEST1,TEST2,TEST3,TEST4,"\n")

include Const2

print(TEST1,TEST2,TEST3,TEST4,"\n")
