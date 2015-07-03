##
# = Trigonometric and transcendental functions for complex numbers.
#
# CMath is a library that provides trigonometric and transcendental
# functions for complex numbers. The functions in this module accept
# integers, floating-point numbers or complex numbers as arguments.
#
# Note that the selection of functions is similar, but not identical,
# to that in module math. The reason for having two modules is that
# some users aren’t interested in complex numbers, and perhaps don’t
# even know what they are. They would rather have Math.sqrt(-1) raise
# an exception than return a complex number.
#
# == Usage
#
# To start using this library, simply require cmath library:
#
#   require "cmath"
#
# And after call any CMath function. For example:
#
#   CMath.sqrt(-9)          #=> 0+3.0i
#   CMath.exp(0 + 0i)       #=> 1.0+0.0i
#   CMath.log10(-5.to_c)    #=> (0.6989700043360187+1.3643763538418412i)
#
#
# For more information you can see Complec class.

module CMath

  include Math

  alias exp! exp
  alias log! log
  alias log2! log2
  alias log10! log10
  alias sqrt! sqrt
  alias cbrt! cbrt

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

  ##
  # Math::E raised to the +z+ power
  #
  #   CMath.exp(2i) #=> (-0.4161468365471424+0.9092974268256817i)
  def exp(z)
    begin
      if z.real?
	exp!(z)
      else
	ere = exp!(z.real)
	Complex(ere * cos!(z.imag),
		ere * sin!(z.imag))
      end
    rescue NoMethodError
      handle_no_method_error
    end
  end

  ##
  # Returns the natural logarithm of Complex. If a second argument is given,
  # it will be the base of logarithm.
  #
  #   CMath.log(1 + 4i)     #=> (1.416606672028108+1.3258176636680326i)
  #   CMath.log(1 + 4i, 10) #=> (0.6152244606891369+0.5757952953408879i)
  def log(*args)
    begin
      z, b = args
      unless b.nil? || b.kind_of?(Numeric)
	raise TypeError,  "Numeric Number required"
      end
      if z.real? and z >= 0 and (b.nil? or b >= 0)
	log!(*args)
      else
	a = Complex(log!(z.abs), z.arg)
	if b
	  a /= log(b)
        end
        a
      end
    rescue NoMethodError
      handle_no_method_error
    end
  end

  ##
  # returns the base 2 logarithm of +z+
  #
  #   CMath.log2(-1) => (0.0+4.532360141827194i)
  def log2(z)
    begin
      if z.real? and z >= 0
	log2!(z)
      else
	log(z) / log!(2)
      end
    rescue NoMethodError
      handle_no_method_error
    end
  end

  ##
  # returns the base 10 logarithm of +z+
  #
  #   CMath.log10(-1) #=> (0.0+1.3643763538418412i)
  def log10(z)
    begin
      if z.real? and z >= 0
	log10!(z)
      else
	log(z) / log!(10)
      end
    rescue NoMethodError
      handle_no_method_error
    end
  end

  ##
  # Returns the non-negative square root of Complex.
  #
  #   CMath.sqrt(-1 + 0i) #=> 0.0+1.0i
  def sqrt(z)
    begin
      if z.real?
	if z < 0
	  Complex(0, sqrt!(-z))
	else
	  sqrt!(z)
	end
      else
	if z.imag < 0 ||
	    (z.imag == 0 && z.imag.to_s[0] == '-')
	  sqrt(z.conjugate).conjugate
	else
	  r = z.abs
	  x = z.real
	  Complex(sqrt!((r + x) / 2.0), sqrt!((r - x) / 2.0))
	end
      end
    rescue NoMethodError
      handle_no_method_error
    end
  end

  ##
  # returns the principal value of the cube root of +z+
  #
  #   CMath.cbrt(1 + 4i) #=> (1.449461632813119+0.6858152562177092i)
  def cbrt(z)
    z ** (1.0/3)
  end

  ##
  # returns the sine of +z+, where +z+ is given in radians
  #
  #   CMath.sin(1 + 1i) #=> (1.2984575814159773+0.6349639147847361i)
  def sin(z)
    begin
      if z.real?
	sin!(z)
      else
	Complex(sin!(z.real) * cosh!(z.imag),
		cos!(z.real) * sinh!(z.imag))
      end
    rescue NoMethodError
      handle_no_method_error
    end
  end

  ##
  # returns the cosine of +z+, where +z+ is given in radians
  #
  #   CMath.cos(1 + 1i) #=> (0.8337300251311491-0.9888977057628651i)
  def cos(z)
    begin
      if z.real?
	cos!(z)
      else
	Complex(cos!(z.real) * cosh!(z.imag),
		-sin!(z.real) * sinh!(z.imag))
      end
    rescue NoMethodError
      handle_no_method_error
    end
  end

  ##
  # returns the tangent of +z+, where +z+ is given in radians
  #
  #   CMath.tan(1 + 1i) #=> (0.27175258531951174+1.0839233273386943i)
  def tan(z)
    begin
      if z.real?
	tan!(z)
      else
	sin(z) / cos(z)
      end
    rescue NoMethodError
      handle_no_method_error
    end
  end

  ##
  # returns the hyperbolic sine of +z+, where +z+ is given in radians
  #
  #   CMath.sinh(1 + 1i) #=> (0.6349639147847361+1.2984575814159773i)
  def sinh(z)
    begin
      if z.real?
	sinh!(z)
      else
	Complex(sinh!(z.real) * cos!(z.imag),
		cosh!(z.real) * sin!(z.imag))
      end
    rescue NoMethodError
      handle_no_method_error
    end
  end

  ##
  # returns the hyperbolic cosine of +z+, where +z+ is given in radians
  #
  #   CMath.cosh(1 + 1i) #=> (0.8337300251311491+0.9888977057628651i)
  def cosh(z)
    begin
      if z.real?
	cosh!(z)
      else
	Complex(cosh!(z.real) * cos!(z.imag),
		sinh!(z.real) * sin!(z.imag))
      end
    rescue NoMethodError
      handle_no_method_error
    end
  end

  ##
  # returns the hyperbolic tangent of +z+, where +z+ is given in radians
  #
  #   CMath.tanh(1 + 1i) #=> (1.0839233273386943+0.27175258531951174i)
  def tanh(z)
    begin
      if z.real?
	tanh!(z)
      else
	sinh(z) / cosh(z)
      end
    rescue NoMethodError
      handle_no_method_error
    end
  end

  ##
  # returns the arc sine of +z+
  #
  #   CMath.asin(1 + 1i) #=> (0.6662394324925153+1.0612750619050355i)
  def asin(z)
    begin
      if z.real? and z >= -1 and z <= 1
	asin!(z)
      else
	(-1.0).i * log(1.0.i * z + sqrt(1.0 - z * z))
      end
    rescue NoMethodError
      handle_no_method_error
    end
  end

  ##
  # returns the arc cosine of +z+
  #
  #   CMath.acos(1 + 1i) #=> (0.9045568943023813-1.0612750619050357i)
  def acos(z)
    begin
      if z.real? and z >= -1 and z <= 1
	acos!(z)
      else
	(-1.0).i * log(z + 1.0.i * sqrt(1.0 - z * z))
      end
    rescue NoMethodError
      handle_no_method_error
    end
  end

  ##
  # returns the arc tangent of +z+
  #
  #   CMath.atan(1 + 1i) #=> (1.0172219678978514+0.4023594781085251i)
  def atan(z)
    begin
      if z.real?
	atan!(z)
      else
	1.0.i * log((1.0.i + z) / (1.0.i - z)) / 2.0
      end
    rescue NoMethodError
      handle_no_method_error
    end
  end

  ##
  # returns the arc tangent of +y+ divided by +x+ using the signs of +y+ and
  # +x+ to determine the quadrant
  #
  #   CMath.atan2(1 + 1i, 0) #=> (1.5707963267948966+0.0i)
  def atan2(y,x)
    begin
      if y.real? and x.real?
	atan2!(y,x)
      else
	(-1.0).i * log((x + 1.0.i * y) / sqrt(x * x + y * y))
      end
    rescue NoMethodError
      handle_no_method_error
    end
  end

  ##
  # returns the inverse hyperbolic sine of +z+
  #
  #   CMath.asinh(1 + 1i) #=> (1.0612750619050357+0.6662394324925153i)
  def asinh(z)
    begin
      if z.real?
	asinh!(z)
      else
	log(z + sqrt(1.0 + z * z))
      end
    rescue NoMethodError
      handle_no_method_error
    end
  end

  ##
  # returns the inverse hyperbolic cosine of +z+
  #
  #   CMath.acosh(1 + 1i) #=> (1.0612750619050357+0.9045568943023813i)
  def acosh(z)
    begin
      if z.real? and z >= 1
	acosh!(z)
      else
	log(z + sqrt(z * z - 1.0))
      end
    rescue NoMethodError
      handle_no_method_error
    end
  end

  ##
  # returns the inverse hyperbolic tangent of +z+
  #
  #   CMath.atanh(1 + 1i) #=> (0.4023594781085251+1.0172219678978514i)
  def atanh(z)
    begin
      if z.real? and z >= -1 and z <= 1
	atanh!(z)
      else
	log((1.0 + z) / (1.0 - z)) / 2.0
      end
    rescue NoMethodError
      handle_no_method_error
    end
  end

  module_function :exp!
  module_function :exp
  module_function :log!
  module_function :log
  module_function :log2!
  module_function :log2
  module_function :log10!
  module_function :log10
  module_function :sqrt!
  module_function :sqrt
  module_function :cbrt!
  module_function :cbrt

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

  module_function :frexp
  module_function :ldexp
  module_function :hypot
  module_function :erf
  module_function :erfc
  module_function :gamma
  module_function :lgamma

  private
  def handle_no_method_error # :nodoc:
    if $!.name == :real?
      raise TypeError, "Numeric Number required"
    else
      raise
    end
  end
  module_function :handle_no_method_error

end
