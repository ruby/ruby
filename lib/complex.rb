#
#   complex.rb - 
#   	$Release Version: 0.5 $
#   	$Revision: 1.3 $
#   	$Date: 1998/07/08 10:05:28 $
#   	by Keiju ISHITSUKA(SHL Japan Inc.)
#
# --
#   Usage:
#      class Complex < Numeric
#
#   Complex(x, y) --> x + yi
#   y.im          --> 0 + yi
#
#   Complex::polar
#
#   Complex::+
#   Complex::-
#   Complex::*
#   Complex::/
#   Complex::**
#   Complex::%
#   Complex::divmod -- obsolete
#   Complex::abs
#   Complex::abs2
#   Complex::arg
#   Complex::polar
#   Complex::conjugate
#   Complex::<=>
#   Complex::==
#   Complex::to_i
#   Complex::to_f
#   Complex::to_r
#   Complex::to_s
#
#   Complex::I
#
#   Numeric::im
#
#   Math.sqrt
#   Math.exp
#   Math.cos
#   Math.sin
#   Math.tan
#   Math.log
#   Math.log10
#   Math.atan2
#
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

class Complex < Numeric
  @RCS_ID='-$Id: complex.rb,v 1.3 1998/07/08 10:05:28 keiju Exp keiju $-'
  
  def Complex.generic?(other)
    other.kind_of?(Integer) or
    other.kind_of?(Float) or
    (defined?(Rational) and other.kind_of?(Rational))
  end

  def Complex.polar(r, theta)
    Complex(r*Math.cos(theta), r*Math.sin(theta))
  end
  
  def initialize(a, b = 0)
    raise "non numeric 1st arg `#{a.inspect}'" if !a.kind_of? Numeric
    raise "non numeric 2nd arg `#{b.inspect}'" if !b.kind_of? Numeric
    @real = a
    @image = b
  end
  
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
  
  def / (other)
    if other.kind_of?(Complex)
      self * other.conjugate / other.abs2
    elsif Complex.generic?(other)
      Complex(@real / other, @image / other)
    else
      x , y = other.coerce(self)
      x / y
    end
  end
  
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
      x , y = other.coerce(self)
      x / y
    end
  end
  
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
  
  def abs
    Math.sqrt!((@real*@real + @image*@image).to_f)
  end
  
  def abs2
    @real*@real + @image*@image
  end
  
  def arg
    Math.atan2(@image.to_f, @real.to_f)
  end
  
  def polar
    return abs, arg
  end
  
  def conjugate
    Complex(@real, -@image)
  end
  
  def <=> (other)
    self.abs <=> other.abs
  end
  
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

  def coerce(other)
    if Complex.generic?(other)
      return Complex.new(other), self
    else
      super
    end
  end

  def to_i
    Complex(@real.to_i, @image.to_i)
  end
  
  def to_f
    Complex(@real.to_f, @image.to_f)
  end
  
  def to_r
    Complex(@real.to_r, @image.to_r)
  end
  
  def denominator
    @real.denominator.lcm(@image.denominator)
  end
  
  def numerator
    cd = denominator
    Complex(@real.numerator*(cd/@real.denominator),
	    @image.numerator*(cd/@image.denominator))
  end
  
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
  
  def hash
    @real ^ @image
  end
  
  def inspect
    sprintf("Complex(%s, %s)", @real.inspect, @image.inspect)
  end

  
  I = Complex(0,1)
  
  attr :real
  attr :image
  
end

class Numeric
  def im
    Complex(0, self)
  end
  
  def real
    self
  end
  
  def image
    0
  end
  
  def arg
    if self >= 0
      return 0
    else
      return Math.atan2(1,1)*4
    end
  end
  
  def polar
    return abs, arg
  end
  
  def conjugate
    self
  end
end

class Fixnum
  if not defined? Rational
    alias power! **
  end
  
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
  alias log10! log10
  alias atan2! atan2
  
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
  
  def exp(z)
    if Complex.generic?(z)
      exp!(z)
    else
      Complex(exp!(z.real) * cos!(z.image), exp!(z.real) * sin!(z.image))
    end
  end
  
  def cosh!(x)
    (exp!(x) + exp!(-x))/2.0
  end
  
  def sinh!(x)
    (exp!(x) - exp!(-x))/2.0
  end
  
  def cos(z)
    if Complex.generic?(z)
      cos!(z)
    else
      Complex(cos!(z.real)*cosh!(z.image),
	      -sin!(z.real)*sinh!(z.image))
    end
  end
    
  def sin(z)
    if Complex.generic?(z)
      sin!(z)
    else
      Complex(sin!(z.real)*cosh!(z.image),
	      cos!(z.real)*sinh!(z.image))
    end
  end
  
  def tan(z)
    if Complex.generic?(z)
      tan!(z)
    else
      sin(z)/cos(z)
    end
  end
  
  def log(z)
    if Complex.generic?(z) and z >= 0
      log!(z)
    else
      r, theta = z.polar
      Complex(log!(r.abs), theta)
    end
  end
  
  def log10(z)
    if Complex.generic?(z)
      log10!(z)
    else
      log(z)/log!(10)
    end
  end
  
  def atan2(x, y)
    if Complex.generic?(x) and Complex.generic?(y)
      atan2!(x, y)
    else
      fail "Not yet implemented."
    end
  end
  
  def atanh!(x)
    log((1.0 + x.to_f) / ( 1.0 - x.to_f)) / 2.0
  end
  
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


