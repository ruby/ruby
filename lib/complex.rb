#
#   complex.rb - 
#   	$Release Version: 0.5 $
#   	$Revision: 1.3 $
#   	$Date: 1998/07/08 10:05:28 $
#   	by Keiju ISHITSUKA(SHL Japan Inc.)
#
# ----
#
# complex.rb implements the Complex class for complex numbers.  Additionally,
# some methods in other Numeric classes are redefined or added to allow greater
# interoperability with Complex numbers.
#
# Complex numbers can be created in the following manner:
# - <tt>Complex(a, b)</tt>
# - <tt>Complex.polar(radius, theta)</tt>
#   
# Additionally, note the following:
# - <tt>Complex::I</tt> (the mathematical constant <i>i</i>)
# - <tt>Numeric#im</tt> (e.g. <tt>5.im -> 0+5i</tt>)
#
# The following +Math+ module methods are redefined to handle Complex arguments.
# They will work as normal with non-Complex arguments.
#    sqrt exp cos sin tan log log10
#    cosh sinh tanh acos asin atan atan2 acosh asinh atanh
#


#
# Numeric is a built-in class on which Fixnum, Bignum, etc., are based.  Here
# some methods are added so that all number types can be treated to some extent
# as Complex numbers.
#
class Numeric
  #
  # Returns a Complex number <tt>(0,<i>self</i>)</tt>.
  #
  def im
    Complex(0, self)
  end
  
  #
  # The real part of a complex number, i.e. <i>self</i>.
  #
  def real
    self
  end
  
  #
  # The imaginary part of a complex number, i.e. 0.
  #
  def image
    0
  end
  alias imag image
  
  #
  # See Complex#arg.
  #
  def arg
    if self >= 0
      return 0
    else
      return Math::PI
    end
  end
  alias angle arg
  
  #
  # See Complex#polar.
  #
  def polar
    return abs, arg
  end
  
  #
  # See Complex#conjugate (short answer: returns <i>self</i>).
  #
  def conjugate
    self
  end
  alias conj conjugate
end


#
# Creates a Complex number.  +a+ and +b+ should be Numeric.  The result will be
# <tt>a+bi</tt>.
#
def Complex(a, b = 0)
  if b == 0 and (a.kind_of?(Complex) or defined? Complex::Unify)
    a
  else
    Complex.new( a.real-b.imag, a.imag+b.real )
  end
end

#
# The complex number class.  See complex.rb for an overview.
#
class Complex < Numeric
  @RCS_ID='-$Id: complex.rb,v 1.3 1998/07/08 10:05:28 keiju Exp keiju $-'

  undef step
  undef div, divmod
  undef floor, truncate, ceil, round

  def Complex.generic?(other) # :nodoc:
    other.kind_of?(Integer) or
    other.kind_of?(Float) or
    (defined?(Rational) and other.kind_of?(Rational))
  end

  #
  # Creates a +Complex+ number in terms of +r+ (radius) and +theta+ (angle).
  #
  def Complex.polar(r, theta)
    Complex(r*Math.cos(theta), r*Math.sin(theta))
  end

  #
  # Creates a +Complex+ number <tt>a</tt>+<tt>b</tt><i>i</i>.
  #
  def Complex.new!(a, b=0)
    new(a,b)
  end

  def initialize(a, b)
    raise TypeError, "non numeric 1st arg `#{a.inspect}'" if !a.kind_of? Numeric
    raise TypeError, "`#{a.inspect}' for 1st arg" if a.kind_of? Complex
    raise TypeError, "non numeric 2nd arg `#{b.inspect}'" if !b.kind_of? Numeric
    raise TypeError, "`#{b.inspect}' for 2nd arg" if b.kind_of? Complex
    @real = a
    @image = b
  end

  #
  # Addition with real or complex number.
  #
  def + (other)
    if other.kind_of?(Complex)
      re = @real + other.real
      im = @image + other.image
      Complex(re, im)
    elsif Complex.generic?(other)
      Complex(@real + other, @image)
    else
      x , y = other.coerce(self)
      x + y
    end
  end
  
  #
  # Subtraction with real or complex number.
  #
  def - (other)
    if other.kind_of?(Complex)
      re = @real - other.real
      im = @image - other.image
      Complex(re, im)
    elsif Complex.generic?(other)
      Complex(@real - other, @image)
    else
      x , y = other.coerce(self)
      x - y
    end
  end
  
  #
  # Multiplication with real or complex number.
  #
  def * (other)
    if other.kind_of?(Complex)
      re = @real*other.real - @image*other.image
      im = @real*other.image + @image*other.real
      Complex(re, im)
    elsif Complex.generic?(other)
      Complex(@real * other, @image * other)
    else
      x , y = other.coerce(self)
      x * y
    end
  end
  
  #
  # Division by real or complex number.
  #
  def / (other)
    if other.kind_of?(Complex)
      self*other.conjugate/other.abs2
    elsif Complex.generic?(other)
      Complex(@real/other, @image/other)
    else
      x, y = other.coerce(self)
      x/y
    end
  end
  
  def quo(other)
    Complex(@real.quo(1), @image.quo(1)) / other
  end

  #
  # Raise this complex number to the given (real or complex) power.
  #
  def ** (other)
    if other == 0
      return Complex(1)
    end
    if other.kind_of?(Complex)
      r, theta = polar
      ore = other.real
      oim = other.image
      nr = Math.exp!(ore*Math.log!(r) - oim * theta)
      ntheta = theta*ore + oim*Math.log!(r)
      Complex.polar(nr, ntheta)
    elsif other.kind_of?(Integer)
      if other > 0
	x = self
	z = x
	n = other - 1
	while n != 0
	  while (div, mod = n.divmod(2)
		 mod == 0)
	    x = Complex(x.real*x.real - x.image*x.image, 2*x.real*x.image)
	    n = div
	  end
	  z *= x
	  n -= 1
	end
	z
      else
	if defined? Rational
	  (Rational(1) / self) ** -other
	else
	  self ** Float(other)
	end
      end
    elsif Complex.generic?(other)
      r, theta = polar
      Complex.polar(r**other, theta*other)
    else
      x, y = other.coerce(self)
      x**y
    end
  end
  
  #
  # Remainder after division by a real or complex number.
  #
  def % (other)
    if other.kind_of?(Complex)
      Complex(@real % other.real, @image % other.image)
    elsif Complex.generic?(other)
      Complex(@real % other, @image % other)
    else
      x , y = other.coerce(self)
      x % y
    end
  end
  
#--
#    def divmod(other)
#      if other.kind_of?(Complex)
#        rdiv, rmod = @real.divmod(other.real)
#        idiv, imod = @image.divmod(other.image)
#        return Complex(rdiv, idiv), Complex(rmod, rmod)
#      elsif Complex.generic?(other)
#        Complex(@real.divmod(other), @image.divmod(other))
#      else
#        x , y = other.coerce(self)
#        x.divmod(y)
#      end
#    end
#++
  
  #
  # Absolute value (aka modulus): distance from the zero point on the complex
  # plane.
  #
  def abs
    Math.hypot(@real, @image)
  end
  
  #
  # Square of the absolute value.
  #
  def abs2
    @real*@real + @image*@image
  end
  
  #
  # Argument (angle from (1,0) on the complex plane).
  #
  def arg
    Math.atan2!(@image, @real)
  end
  alias angle arg
  
  #
  # Returns the absolute value _and_ the argument.
  #
  def polar
    return abs, arg
  end
  
  #
  # Complex conjugate (<tt>z + z.conjugate = 2 * z.real</tt>).
  #
  def conjugate
    Complex(@real, -@image)
  end
  alias conj conjugate
  
  #
  # Compares the absolute values of the two numbers.
  #
  def <=> (other)
    self.abs <=> other.abs
  end
  
  #
  # Test for numerical equality (<tt>a == a + 0<i>i</i></tt>).
  #
  def == (other)
    if other.kind_of?(Complex)
      @real == other.real and @image == other.image
    elsif Complex.generic?(other)
      @real == other and @image == 0
    else
      other == self
    end
  end

  #
  # Attempts to coerce +other+ to a Complex number.
  #
  def coerce(other)
    if Complex.generic?(other)
      return Complex.new!(other), self
    else
      super
    end
  end

  #
  # FIXME
  #
  def denominator
    @real.denominator.lcm(@image.denominator)
  end
  
  #
  # FIXME
  #
  def numerator
    cd = denominator
    Complex(@real.numerator*(cd/@real.denominator),
	    @image.numerator*(cd/@image.denominator))
  end
  
  #
  # Standard string representation of the complex number.
  #
  def to_s
    if @real != 0
      if defined?(Rational) and @image.kind_of?(Rational) and @image.denominator != 1
	if @image >= 0
	  @real.to_s+"+("+@image.to_s+")i"
	else
	  @real.to_s+"-("+(-@image).to_s+")i"
	end
      else
	if @image >= 0
	  @real.to_s+"+"+@image.to_s+"i"
	else
	  @real.to_s+"-"+(-@image).to_s+"i"
	end
      end
    else
      if defined?(Rational) and @image.kind_of?(Rational) and @image.denominator != 1
	"("+@image.to_s+")i"
      else
	@image.to_s+"i"
      end
    end
  end
  
  #
  # Returns a hash code for the complex number.
  #
  def hash
    @real.hash ^ @image.hash
  end
  
  #
  # Returns "<tt>Complex(<i>real</i>, <i>image</i>)</tt>".
  #
  def inspect
    sprintf("Complex(%s, %s)", @real.inspect, @image.inspect)
  end

  
  #
  # +I+ is the imaginary number.  It exists at point (0,1) on the complex plane.
  #
  I = Complex(0,1)
  
  # The real part of a complex number.
  attr :real

  # The imaginary part of a complex number.
  attr :image
  alias imag image
  
end

class Integer

  unless defined?(1.numerator)
    def numerator() self end
    def denominator() 1 end

    def gcd(other)
      min = self.abs
      max = other.abs
      while min > 0
        tmp = min
        min = max % min
        max = tmp
      end
      max
    end

    def lcm(other)
      if self.zero? or other.zero?
        0
      else
        (self.div(self.gcd(other)) * other).abs
      end
    end

  end

end

module Math
  alias sqrt! sqrt
  alias exp! exp
  alias log! log
  alias log10! log10
  alias cos! cos
  alias sin! sin
  alias tan! tan
  alias cosh! cosh
  alias sinh! sinh
  alias tanh! tanh
  alias acos! acos
  alias asin! asin
  alias atan! atan
  alias atan2! atan2
  alias acosh! acosh
  alias asinh! asinh
  alias atanh! atanh  

  # Redefined to handle a Complex argument.
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
	Complex( sqrt!((r+x)/2), sqrt!((r-x)/2) )
      end
    end
  end
  
  # Redefined to handle a Complex argument.
  def exp(z)
    if Complex.generic?(z)
      exp!(z)
    else
      Complex(exp!(z.real) * cos!(z.image), exp!(z.real) * sin!(z.image))
    end
  end
  
  # Redefined to handle a Complex argument.
  def cos(z)
    if Complex.generic?(z)
      cos!(z)
    else
      Complex(cos!(z.real)*cosh!(z.image),
	      -sin!(z.real)*sinh!(z.image))
    end
  end
    
  # Redefined to handle a Complex argument.
  def sin(z)
    if Complex.generic?(z)
      sin!(z)
    else
      Complex(sin!(z.real)*cosh!(z.image),
	      cos!(z.real)*sinh!(z.image))
    end
  end
  
  # Redefined to handle a Complex argument.
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
      Complex( sinh!(z.real)*cos!(z.image), cosh!(z.real)*sin!(z.image) )
    end
  end

  def cosh(z)
    if Complex.generic?(z)
      cosh!(z)
    else
      Complex( cosh!(z.real)*cos!(z.image), sinh!(z.real)*sin!(z.image) )
    end
  end

  def tanh(z)
    if Complex.generic?(z)
      tanh!(z)
    else
      sinh(z)/cosh(z)
    end
  end
  
  # Redefined to handle a Complex argument.
  def log(z)
    if Complex.generic?(z) and z >= 0
      log!(z)
    else
      r, theta = z.polar
      Complex(log!(r.abs), theta)
    end
  end
  
  # Redefined to handle a Complex argument.
  def log10(z)
    if Complex.generic?(z)
      log10!(z)
    else
      log(z)/log!(10)
    end
  end

  def acos(z)
    if Complex.generic?(z) and z >= -1 and z <= 1
      acos!(z)
    else
      -1.0.im * log( z + 1.0.im * sqrt(1.0-z*z) )
    end
  end

  def asin(z)
    if Complex.generic?(z) and z >= -1 and z <= 1
      asin!(z)
    else
      -1.0.im * log( 1.0.im * z + sqrt(1.0-z*z) )
    end
  end

  def atan(z)
    if Complex.generic?(z)
      atan!(z)
    else
      1.0.im * log( (1.0.im+z) / (1.0.im-z) ) / 2.0
    end
  end

  def atan2(y,x)
    if Complex.generic?(y) and Complex.generic?(x)
      atan2!(y,x)
    else
      -1.0.im * log( (x+1.0.im*y) / sqrt(x*x+y*y) )
    end
  end

  def acosh(z)
    if Complex.generic?(z) and z >= 1
      acosh!(z)
    else
      log( z + sqrt(z*z-1.0) )
    end
  end

  def asinh(z)
    if Complex.generic?(z)
      asinh!(z)
    else
      log( z + sqrt(1.0+z*z) )
    end
  end

  def atanh(z)
    if Complex.generic?(z) and z >= -1 and z <= 1
      atanh!(z)
    else
      log( (1.0+z) / (1.0-z) ) / 2.0
    end
  end

  module_function :sqrt!
  module_function :sqrt
  module_function :exp!
  module_function :exp
  module_function :log!
  module_function :log
  module_function :log10!
  module_function :log10
  module_function :cosh!
  module_function :cosh
  module_function :cos!
  module_function :cos
  module_function :sinh!
  module_function :sinh
  module_function :sin!
  module_function :sin
  module_function :tan!
  module_function :tan
  module_function :tanh!
  module_function :tanh
  module_function :acos!
  module_function :acos
  module_function :asin!
  module_function :asin
  module_function :atan!
  module_function :atan
  module_function :atan2!
  module_function :atan2
  module_function :acosh!
  module_function :acosh
  module_function :asinh!
  module_function :asinh
  module_function :atanh!
  module_function :atanh
  
end

# Documentation comments:
#  - source: original (researched from pickaxe)
#  - a couple of fixme's
#  - RDoc output for Bignum etc. is a bit short, with nothing but an
#    (undocumented) alias.  No big deal.
