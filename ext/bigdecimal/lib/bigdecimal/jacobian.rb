#
# jacobian.rb
#
# Computes Jacobian matrix of f at x
#
module Jacobian
  def isEqual(a,b,zero=0.0,e=1.0e-8)
    aa = a.abs
    bb = b.abs
    if aa == zero &&  bb == zero then
          true
    else
          if ((a-b)/(aa+bb)).abs < e then
             true
          else
             false
          end
    end
  end

  def dfdxi(f,fx,x,i)
    nRetry = 0
    n = x.size
    xSave = x[i]
    ok = 0
    ratio = f.ten*f.ten*f.ten
    dx = x[i].abs/ratio
    dx = fx[i].abs/ratio if isEqual(dx,f.zero,f.zero,f.eps)
    dx = f.one/f.ten     if isEqual(dx,f.zero,f.zero,f.eps)
    until ok>0 do
      s = f.zero
      deriv = []
      if(nRetry>100) then
         raize "Singular Jacobian matrix. No change at x[" + i.to_s + "]"
      end
      dx = dx*f.two
      x[i] += dx
      fxNew = f.values(x)
      for j in 0...n do
        if !isEqual(fxNew[j],fx[j],f.zero,f.eps) then
           ok += 1
           deriv <<= (fxNew[j]-fx[j])/dx
        else
           deriv <<= f.zero
        end
      end
      x[i] = xSave
    end
    deriv
  end

  def jacobian(f,fx,x)
    n = x.size
    dfdx = Array::new(n*n)
    for i in 0...n do
      df = dfdxi(f,fx,x,i)
      for j in 0...n do
         dfdx[j*n+i] = df[j]
      end
    end
    dfdx
  end
end
