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
# - <tt>Complex.new(a, b)</tt>
# - <tt>Complex.polar(radius, theta)</tt>
#   
# Additionally, note the following:
# - <tt>Complex::I</tt> (the mathematical constant <i>i</i>)
# - <tt>Numeric#im</tt> (e.g. <tt>5.im -> 0+5i</tt>)
#
# The following +Math+ module methods are redefined to handle Complex arguments.
# They will work as normal with non-Complex arguments.
#    sqrt exp cos sin tan log log10 atan2
#


#
# Creates a Complex number.  +a+ and +b+ should be Numeric.  The result will be
# <tt>a+bi</tt>.
#
def Complex(a, b = 0)
  if a.kind_of?(Complex) and b == 0
    a
  elsif b.kind_of?(Complex)
    if a.kind_of?(Complex)
      Complex(a.real-b.image, a.image + b.real)
    else
      Complex(a-b.image, b.real)
    end
  elsif b == 0 and defined? Complex::Unify
    a
  else
    Complex.new(a, b)
  end
end

#
# The complex number class.  See complex.rb for an overview.
#
class Complex < Numeric
  @RCS_ID='-$Id: complex.rb,v 1.3 1998/07/08 10:05:28 keiju Exp keiju $-'

  undef step

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
  def initialize(a, b = 0)
    raise "non numeric 1st arg `#{a.inspect}'" if !a.kind_of? Numeric
    raise "non numeric 2nd arg `#{b.inspect}'" if !b.kind_of? Numeric
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
      Complex.polar(r.power!(other), theta * other)
    else
      x, y = other.coerce(self)
      x/y
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
    Math.sqrt!((@real*@real + @image*@image).to_f)
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
    Math.atan2(@image.to_f, @real.to_f)
  end
  
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
      x , y = other.coerce(self)
      x == y
    end
  end

  #
  # Attempts to coerce +other+ to a Complex number.
  #
  def coerce(other)
    if Complex.generic?(other)
      return Complex.new(other), self
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
  
end


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
  
  #
  # See Complex#arg.
  #
  def arg
    if self >= 0
      return 0
    else
      return Math.atan2(1,1)*4
    end
  end
  
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
end


class Fixnum
  if not defined? Rational
    alias power! **
  end
  
  # Redefined to handle a Complex argument.
  def ** (other)
    if self < 0
      Complex.new(self) ** other
    else
      if defined? Rational
	if other >= 0
	  self.power!(other)
	else
	  Rational.new!(self,1)**other
	end
      else
	self.power!(other)
      end
    end
  end
end

class Bignum
  if not defined? Rational
    alias power! **
  end
end

class Float
  alias power! **
end

module Math
  alias sqrt! sqrt
  alias exp! exp
  alias cos! cos
  alias sin! sin
  alias tan! tan
  alias log! log
  alias atan! atan  
  alias log10! log10
  alias atan2! atan2

  # Redefined to handle a Complex argument.
  def sqrt(z)
    if Complex.generic?(z)
      if z >= 0
	sqrt!(z)
      else
	Complex(0,sqrt!(-z))
      end
    else
      z**Rational(1,2)
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
  
  #
  # Hyperbolic cosine.
  #
  def cosh!(x)
    (exp!(x) + exp!(-x))/2.0
  end
  
  #
  # Hyperbolic sine.
  #
  def sinh!(x)
    (exp!(x) - exp!(-x))/2.0
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
  
  # FIXME: I don't know what the point of this is.  If you give it Complex
  # arguments, it will fail.
  def atan2(x, y)
    if Complex.generic?(x) and Complex.generic?(y)
      atan2!(x, y)
    else
      fail "Not yet implemented."
    end
  end
  
  #
  # Hyperbolic arctangent.
  #
  def atanh!(x)
    log((1.0 + x.to_f) / ( 1.0 - x.to_f)) / 2.0
  end
  
  # Redefined to handle a Complex argument.
  def atan(z)
    if Complex.generic?(z)
      atan2!(z, 1)
    elsif z.image == 0
      atan2(z.real,1)
    else
      a = z.real
      b = z.image
      
      c = (a*a + b*b - 1.0)
      d = (a*a + b*b + 1.0)

      Complex(atan2!((c + sqrt(c*c + 4.0*a*a)), 2.0*a),
	      atanh!((-d + sqrt(d*d - 4.0*b*b))/(2.0*b)))
    end
  end
  
  module_function :sqrt
  module_function :sqrt!
  module_function :exp!
  module_function :exp
  module_function :cosh!
  module_function :cos!
  module_function :cos
  module_function :sinh!
  module_function :sin!
  module_function :sin
  module_function :tan!
  module_function :tan
  module_function :log!
  module_function :log
  module_function :log10!
  module_function :log
  module_function :atan2!
  module_function :atan2
#  module_function :atan!
  module_function :atan
  module_function :atanh!
  
end


# Documentation comments:
#  - source: original (researched from pickaxe)
#  - a couple of fixme's
#  - Math module methods sinh! etc. a bit fuzzy.  What exactly is the intention?
#  - RDoc output for Bignum etc. is a bit short, with nothing but an
#    (undocumented) alias.  No big deal.
