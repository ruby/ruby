module CMath

  include Math

  alias exp! exp
  alias log! log
  alias log10! log10
  alias sqrt! sqrt

  alias sin! sin
  alias cos! cos
  alias tan! tan

  alias sinh! sinh
  alias cosh! cosh
  alias tanh! tanh

  alias asin! asin
  alias acos! acos
  alias atan! atan
  alias atan2! atan2

  alias asinh! asinh
  alias acosh! acosh
  alias atanh! atanh

  def exp(z)
    if z.real?
      exp!(z)
    else
      Complex(exp!(z.real) * cos!(z.imag),
	      exp!(z.real) * sin!(z.imag))
    end
  end

  def log(*args)
    z, b = args
    if z.real? and z >= 0 and (b.nil? or b >= 0)
      log!(*args)
    else
      r, theta = z.polar
      a = Complex(log!(r.abs), theta)
      if b
	a /= log(b)
      end
      a
    end
  end

  def log10(z)
    if z.real?
      log10!(z)
    else
      log(z) / log!(10)
    end
  end

  def sqrt(z)
    if z.real?
      if z < 0
	Complex(0, sqrt!(-z))
      else
	sqrt!(z)
      end
    else
      if z.imag < 0
	sqrt(z.conjugate).conjugate
      else
	r = z.abs
	x = z.real
	Complex(sqrt!((r + x) / 2), sqrt!((r - x) / 2))
      end
    end
  end

  def sin(z)
    if z.real?
      sin!(z)
    else
      Complex(sin!(z.real) * cosh!(z.imag),
	      cos!(z.real) * sinh!(z.imag))
    end
  end

  def cos(z)
    if z.real?
      cos!(z)
    else
      Complex(cos!(z.real) * cosh!(z.imag),
	      -sin!(z.real) * sinh!(z.imag))
    end
  end

  def tan(z)
    if z.real?
      tan!(z)
    else
      sin(z)/cos(z)
    end
  end

  def sinh(z)
    if z.real?
      sinh!(z)
    else
      Complex(sinh!(z.real) * cos!(z.imag),
	      cosh!(z.real) * sin!(z.imag))
    end
  end

  def cosh(z)
    if z.real?
      cosh!(z)
    else
      Complex(cosh!(z.real) * cos!(z.imag),
	      sinh!(z.real) * sin!(z.imag))
    end
  end

  def tanh(z)
    if z.real?
      tanh!(z)
    else
      sinh(z) / cosh(z)
    end
  end

  def asin(z)
    if z.real? and z >= -1 and z <= 1
      asin!(z)
    else
      Complex(0, -1.0) * log(Complex(0, 1.0) * z + sqrt(1.0 - z * z))
    end
  end

  def acos(z)
    if z.real? and z >= -1 and z <= 1
      acos!(z)
    else
      Complex(0, -1.0) * log(z + Complex(0, 1.0) * sqrt(1.0 - z * z))
    end
  end

  def atan(z)
    if z.real?
      atan!(z)
    else
      Complex(0, 1.0) * log((Complex(0, 1.0) + z) / (Complex(0, 1.0) - z)) / 2.0
    end
  end

  def atan2(y,x)
    if y.real? and x.real?
      atan2!(y,x)
    else
      Complex(0, -1.0) * log((x + Complex(0, 1.0) * y) / sqrt(x * x + y * y))
    end
  end

  def acosh(z)
    if z.real? and z >= 1
      acosh!(z)
    else
      log(z + sqrt(z * z - 1.0))
    end
  end

  def asinh(z)
    if z.real?
      asinh!(z)
    else
      log(z + sqrt(1.0 + z * z))
    end
  end

  def atanh(z)
    if z.real? and z >= -1 and z <= 1
      atanh!(z)
    else
      log((1.0 + z) / (1.0 - z)) / 2.0
    end
  end

  module_function :exp!
  module_function :exp
  module_function :log!
  module_function :log
  module_function :log10!
  module_function :log10
  module_function :sqrt!
  module_function :sqrt

  module_function :sin!
  module_function :sin
  module_function :cos!
  module_function :cos
  module_function :tan!
  module_function :tan

  module_function :sinh!
  module_function :sinh
  module_function :cosh!
  module_function :cosh
  module_function :tanh!
  module_function :tanh

  module_function :asin!
  module_function :asin
  module_function :acos!
  module_function :acos
  module_function :atan!
  module_function :atan
  module_function :atan2!
  module_function :atan2

  module_function :asinh!
  module_function :asinh
  module_function :acosh!
  module_function :acosh
  module_function :atanh!
  module_function :atanh

  module_function :log2
  module_function :cbrt
  module_function :frexp
  module_function :ldexp
  module_function :hypot
  module_function :erf
  module_function :erfc
  module_function :gamma
  module_function :lgamma

end
