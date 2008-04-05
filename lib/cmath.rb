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
    if Complex.generic?(z)
      exp!(z)
    else
      Complex(exp!(z.real) * cos!(z.image),
	      exp!(z.real) * sin!(z.image))
    end
  end

  def log(*args)
    z, b = args
    if Complex.generic?(z) and z >= 0 and (b.nil? or b >= 0)
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
    if Complex.generic?(z)
      log10!(z)
    else
      log(z) / log!(10)
    end
  end

  def sqrt(z)
    if Complex.generic?(z)
      if z >= 0
	sqrt!(z)
      else
	Complex(0,sqrt!(-z))
      end
    else
      if z.image < 0
	sqrt(z.conjugate).conjugate
      else
	r = z.abs
	x = z.real
	Complex(sqrt!((r + x) / 2), sqrt!((r - x) / 2))
      end
    end
  end

  def sin(z)
    if Complex.generic?(z)
      sin!(z)
    else
      Complex(sin!(z.real) * cosh!(z.image),
	      cos!(z.real) * sinh!(z.image))
    end
  end

  def cos(z)
    if Complex.generic?(z)
      cos!(z)
    else
      Complex(cos!(z.real) * cosh!(z.image),
	      -sin!(z.real) * sinh!(z.image))
    end
  end

  def tan(z)
    if Complex.generic?(z)
      tan!(z)
    else
      sin(z)/cos(z)
    end
  end

  def sinh(z)
    if Complex.generic?(z)
      sinh!(z)
    else
      Complex(sinh!(z.real) * cos!(z.image),
	      cosh!(z.real) * sin!(z.image))
    end
  end

  def cosh(z)
    if Complex.generic?(z)
      cosh!(z)
    else
      Complex(cosh!(z.real) * cos!(z.image),
	      sinh!(z.real) * sin!(z.image))
    end
  end

  def tanh(z)
    if Complex.generic?(z)
      tanh!(z)
    else
      sinh(z) / cosh(z)
    end
  end

  def asin(z)
    if Complex.generic?(z) and z >= -1 and z <= 1
      asin!(z)
    else
      -1.0.im * log(1.0.im * z + sqrt(1.0 - z * z))
    end
  end

  def acos(z)
    if Complex.generic?(z) and z >= -1 and z <= 1
      acos!(z)
    else
      -1.0.im * log(z + 1.0.im * sqrt(1.0 - z * z))
    end
  end

  def atan(z)
    if Complex.generic?(z)
      atan!(z)
    else
      1.0.im * log((1.0.im + z) / (1.0.im - z)) / 2.0
    end
  end

  def atan2(y,x)
    if Complex.generic?(y) and Complex.generic?(x)
      atan2!(y,x)
    else
      -1.0.im * log((x + 1.0.im * y) / sqrt(x * x + y * y))
    end
  end

  def acosh(z)
    if Complex.generic?(z) and z >= 1
      acosh!(z)
    else
      log(z + sqrt(z * z - 1.0))
    end
  end

  def asinh(z)
    if Complex.generic?(z)
      asinh!(z)
    else
      log(z + sqrt(1.0 + z * z))
    end
  end

  def atanh(z)
    if Complex.generic?(z) and z >= -1 and z <= 1
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

end
