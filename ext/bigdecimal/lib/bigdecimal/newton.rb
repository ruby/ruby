#
# newton.rb 
#
# Solves nonlinear algebraic equation system f = 0 by Newton's method.
#  (This program is not dependent on BigDecimal)
#
# To call:
#    n = nlsolve(f,x)
#  where n is the number of iterations required.
#        x is the solution vector.
#        f is the object to be solved which must have following methods.
#
#   f ... Object to compute Jacobian matrix of the equation systems.
#       [Methods required for f]
#         f.values(x) returns values of all functions at x.
#         f.zero      returns 0.0
#         f.one       returns 1.0
#         f.two       returns 1.0
#         f.ten       returns 10.0
#         f.eps       convergence criterion
#   x ... initial values
#
require "bigdecimal/ludcmp"
require "bigdecimal/jacobian"

module Newton
  include LUSolve
  include Jacobian
  
  def norm(fv,zero=0.0)
    s = zero
    n = fv.size
    for i in 0...n do
      s += fv[i]*fv[i]
    end
    s
  end

  def nlsolve(f,x)
    nRetry = 0
    n = x.size

    f0 = f.values(x)
    zero = f.zero
    one  = f.one
    two  = f.two
    p5 = one/two
    d  = norm(f0,zero)
    minfact = f.ten*f.ten*f.ten
    minfact = one/minfact
    e = f.eps
    while d >= e do
      nRetry += 1
      # Not yet converged. => Compute Jacobian matrix
      dfdx = jacobian(f,f0,x)
      # Solve dfdx*dx = -f0 to estimate dx
      dx = lusolve(dfdx,f0,ludecomp(dfdx,n,zero,one),zero)
      fact = two
      xs = x.dup
      begin
        fact *= p5
        if fact < minfact then
          raize "Failed to reduce function values."
        end
        for i in 0...n do
          x[i] = xs[i] - dx[i]*fact
        end
        f0 = f.values(x)
        dn = norm(f0,zero)
      end while(dn>=d)
      d = dn
    end
    nRetry
  end
end
