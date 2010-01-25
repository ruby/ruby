#
#   mathn.rb -
#   	$Release Version: 0.5 $
#   	$Revision: 1.1.1.1.4.1 $
#   	by Keiju ISHITSUKA(SHL Japan Inc.)
#
# --
#
#
#

require "cmath.rb"
require "matrix.rb"
require "prime.rb"

require "mathn/rational"
require "mathn/complex"

unless defined?(Math.exp!)
  Object.instance_eval{remove_const :Math}
  Math = CMath
end

class Fixnum
  remove_method :/
  alias / quo

  alias power! ** unless method_defined? :power!

  def ** (other)
    if self < 0 && other.round != other
      Complex(self, 0.0) ** other
    else
      power!(other)
    end
  end

end

class Bignum
  remove_method :/
  alias / quo

  alias power! ** unless method_defined? :power!

  def ** (other)
    if self < 0 && other.round != other
      Complex(self, 0.0) ** other
    else
      power!(other)
    end
  end

end

class Rational
  remove_method :**
  def ** (other)
    if other.kind_of?(Rational)
      other2 = other
      if self < 0
	return Complex(self, 0.0) ** other
      elsif other == 0
	return Rational(1,1)
      elsif self == 0
	return Rational(0,1)
      elsif self == 1
	return Rational(1,1)
      end

      npd = numerator.prime_division
      dpd = denominator.prime_division
      if other < 0
	other = -other
	npd, dpd = dpd, npd
      end

      for elm in npd
	elm[1] = elm[1] * other
	if !elm[1].kind_of?(Integer) and elm[1].denominator != 1
         return Float(self) ** other2
	end
	elm[1] = elm[1].to_i
      end

      for elm in dpd
	elm[1] = elm[1] * other
	if !elm[1].kind_of?(Integer) and elm[1].denominator != 1
         return Float(self) ** other2
	end
	elm[1] = elm[1].to_i
      end

      num = Integer.from_prime_division(npd)
      den = Integer.from_prime_division(dpd)

      Rational(num,den)

    elsif other.kind_of?(Integer)
      if other > 0
	num = numerator ** other
	den = denominator ** other
      elsif other < 0
	num = denominator ** -other
	den = numerator ** -other
      elsif other == 0
	num = 1
	den = 1
      end
      Rational(num, den)
    elsif other.kind_of?(Float)
      Float(self) ** other
    else
      x , y = other.coerce(self)
      x ** y
    end
  end
end

module Math
  remove_method(:sqrt)
  def sqrt(a)
    if a.kind_of?(Complex)
      abs = sqrt(a.real*a.real + a.imag*a.imag)
#      if not abs.kind_of?(Rational)
#	return a**Rational(1,2)
#      end
      x = sqrt((a.real + abs)/Rational(2))
      y = sqrt((-a.real + abs)/Rational(2))
#      if !(x.kind_of?(Rational) and y.kind_of?(Rational))
#	return a**Rational(1,2)
#      end
      if a.imag >= 0
	Complex(x, y)
      else
	Complex(x, -y)
      end
    elsif a.respond_to?(:nan?) and a.nan?
      a
    elsif a >= 0
      rsqrt(a)
    else
      Complex(0,rsqrt(-a))
    end
  end

  def rsqrt(a)
    if a.kind_of?(Float)
      sqrt!(a)
    elsif a.kind_of?(Rational)
      rsqrt(a.numerator)/rsqrt(a.denominator)
    else
      src = a
      max = 2 ** 32
      byte_a = [src & 0xffffffff]
      # ruby's bug
      while (src >= max) and (src >>= 32)
	byte_a.unshift src & 0xffffffff
      end

      answer = 0
      main = 0
      side = 0
      for elm in byte_a
	main = (main << 32) + elm
	side <<= 16
	if answer != 0
	  if main * 4  < side * side
	    applo = main.div(side)
	  else
	    applo = ((sqrt!(side * side + 4 * main) - side)/2.0).to_i + 1
	  end
	else
	  applo = sqrt!(main).to_i + 1
	end

	while (x = (side + applo) * applo) > main
	  applo -= 1
	end
	main -= x
	answer = (answer << 16) + applo
	side += applo * 2
      end
      if main == 0
	answer
      else
	sqrt!(a)
      end
    end
  end

  class << self
    remove_method(:sqrt)
  end
  module_function :sqrt
  module_function :rsqrt
end

class Float
  alias power! **

  def ** (other)
    if self < 0 && other.round != other
      Complex(self, 0.0) ** other
    else
      power!(other)
    end
  end

end
