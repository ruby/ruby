#!/usr/local/bin/ruby

#
# linear.rb
#
# Solves linear equation system(A*x = b) by LU decomposition method.
#  where  A is a coefficient matrix,x is an answer vector,b is a constant vector.
#
require "bigdecimal"
require "ludcmp"

include LUSolve

def rd_order
   printf("Number of equations ?")
   n = gets().chomp.to_i
end

zero = BigDecimal::new("0.0")
one  = BigDecimal::new("1.0")

while (n=rd_order())>0
  a = []
  as= []
  b = []
  printf("\nEnter coefficient matrix element A[i,j]\n");
  for i in 0...n do
    for j in 0...n do
      printf("A[%d,%d]? ",i,j); s = gets
      a <<=BigDecimal::new(s);
      as<<=BigDecimal::new(s);
    end
    printf("Contatant vector element b[%d] ? ",i);b<<=BigDecimal::new(gets);
  end
  printf "ANS="
  x = lusolve(a,b,ludecomp(a,n,zero,one),zero)
  p x
  printf "A*x-b\n"
  for i in 0...n do
    s = zero
    for j in 0...n do
       s = s + as[i*n+j]*x[j]
    end
    p s-b[i]
  end
end
