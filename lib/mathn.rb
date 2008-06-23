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

require "complex.rb"
require "rational.rb"
require "matrix.rb"

class Integer

  def Integer.from_prime_division(pd)
    value = 1
    for prime, index in pd
      value *= prime**index
    end
    value
  end
  
  def prime_division
    raise ZeroDivisionError if self == 0
    ps = Prime.new
    value = self
    pv = []
    for prime in ps
      count = 0
      while (value1, mod = value.divmod(prime)
	     mod) == 0
	value = value1
	count += 1
      end
      if count != 0
	pv.push [prime, count]
      end
      break if prime * prime  >= value
    end
    if value > 1
      pv.push [value, 1]
    end
    return pv
  end
end
  
class Prime
  include Enumerable
  # These are included as class variables to cache them for later uses.  If memory
  #   usage is a problem, they can be put in Prime#initialize as instance variables.

  # There must be no primes between @@primes[-1] and @@next_to_check.
  @@primes = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97, 101]
  # @@next_to_check % 6 must be 1.  
  @@next_to_check = 103            # @@primes[-1] - @@primes[-1] % 6 + 7
  @@ulticheck_index = 3            # @@primes.index(@@primes.reverse.find {|n|
                                   #   n < Math.sqrt(@@next_to_check) })
  @@ulticheck_next_squared = 121   # @@primes[@@ulticheck_index + 1] ** 2

  class << self
    # Return the prime cache.
    def cache
      return @@primes
    end
    alias primes cache
    alias primes_so_far cache
  end
  
  def initialize
    @index = -1
  end
  
  # Return primes given by this instance so far.
  def primes
    return @@primes[0, @index + 1]
  end
  alias primes_so_far primes
  
  def succ
    @index += 1
    while @index >= @@primes.length
      # Only check for prime factors up to the square root of the potential primes,
      #   but without the performance hit of an actual square root calculation.
      if @@next_to_check + 4 > @@ulticheck_next_squared
        @@ulticheck_index += 1
        @@ulticheck_next_squared = @@primes.at(@@ulticheck_index + 1) ** 2
      end
      # Only check numbers congruent to one and five, modulo six. All others
      #   are divisible by two or three.  This also allows us to skip checking against
      #   two and three.
      @@primes.push @@next_to_check if @@primes[2..@@ulticheck_index].find {|prime| @@next_to_check % prime == 0 }.nil?
      @@next_to_check += 4
      @@primes.push @@next_to_check if @@primes[2..@@ulticheck_index].find {|prime| @@next_to_check % prime == 0 }.nil?
      @@next_to_check += 2 
    end
    return @@primes[@index]
  end
  alias next succ

  def each
    return to_enum(:each) unless block_given?
    loop do
      yield succ
    end
  end
end

class Fixnum
  remove_method :/
  alias / quo
end

class Bignum
  remove_method :/
  alias / quo
end

class Rational
  Unify = true

  alias power! **

  def ** (other)
    if other.kind_of?(Rational)
      other2 = other
      if self < 0
	return Complex.__send__(:new!, self, 0) ** other
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
      abs = sqrt(a.real*a.real + a.image*a.image)
#      if not abs.kind_of?(Rational)
#	return a**Rational(1,2)
#      end
      x = sqrt((a.real + abs)/Rational(2))
      y = sqrt((-a.real + abs)/Rational(2))
#      if !(x.kind_of?(Rational) and y.kind_of?(Rational))
#	return a**Rational(1,2)
#      end
      if a.image >= 0 
	Complex(x, y)
      else
	Complex(x, -y)
      end
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

  module_function :sqrt
  module_function :rsqrt
end

class Complex
  Unify = true
end
