#
#   rational.rb -
#       $Release Version: 0.5 $
#       $Revision: 1.7 $
#       $Date: 1999/08/24 12:49:28 $
#       by Keiju ISHITSUKA(SHL Japan Inc.)
#
# Documentation by Kevin Jackson and Gavin Sinclair.
# 
# When you <tt>require 'rational'</tt>, all interactions between numbers
# potentially return a rational result.  For example:
#
#   1.quo(2)              # -> 0.5
#   require 'rational'
#   1.quo(2)              # -> Rational(1,2)
# 
# See Rational for full documentation.
#


#
# Creates a Rational number (i.e. a fraction).  +a+ and +b+ should be Integers:
# 
#   Rational(1,3)           # -> 1/3
#
# Note: trying to construct a Rational with floating point or real values
# produces errors:
#
#   Rational(1.1, 2.3)      # -> NoMethodError
#
def Rational(a, b = 1)
  if a.kind_of?(Rational) && b == 1
    a
  else
    Rational.reduce(a, b)
  end
end

#
# Rational implements a rational class for numbers.
#
# <em>A rational number is a number that can be expressed as a fraction p/q
# where p and q are integers and q != 0.  A rational number p/q is said to have
# numerator p and denominator q.  Numbers that are not rational are called
# irrational numbers.</em> (http://mathworld.wolfram.com/RationalNumber.html)
#
# To create a Rational Number:
#   Rational(a,b)             # -> a/b
#   Rational.new!(a,b)        # -> a/b
#
# Examples:
#   Rational(5,6)             # -> 5/6
#   Rational(5)               # -> 5/1
# 
# Rational numbers are reduced to their lowest terms:
#   Rational(6,10)            # -> 3/5
#
# But not if you use the unusual method "new!":
#   Rational.new!(6,10)       # -> 6/10
#
# Division by zero is obviously not allowed:
#   Rational(3,0)             # -> ZeroDivisionError
#
class Rational < Numeric
  @RCS_ID='-$Id: rational.rb,v 1.7 1999/08/24 12:49:28 keiju Exp keiju $-'

  #
  # Reduces the given numerator and denominator to their lowest terms.  Use
  # Rational() instead.
  #
  def Rational.reduce(num, den = 1)
    raise ZeroDivisionError, "denominator is zero" if den == 0

    if den < 0
      num = -num
      den = -den
    end
    gcd = num.gcd(den)
    num = num.div(gcd)
    den = den.div(gcd)
    if den == 1 && defined?(Unify)
      num
    else
      new!(num, den)
    end
  end

  #
  # Implements the constructor.  This method does not reduce to lowest terms or
  # check for division by zero.  Therefore #Rational() should be preferred in
  # normal use.
  #
  def Rational.new!(num, den = 1)
    new(num, den)
  end

  private_class_method :new

  #
  # This method is actually private.
  #
  def initialize(num, den)
    if den < 0
      num = -num
      den = -den
    end
    if num.kind_of?(Integer) and den.kind_of?(Integer)
      @numerator = num
      @denominator = den
    else
      @numerator = num.to_i
      @denominator = den.to_i
    end
  end

  #
  # Returns the addition of this value and +a+.
  #
  # Examples:
  #   r = Rational(3,4)      # -> Rational(3,4)
  #   r + 1                  # -> Rational(7,4)
  #   r + 0.5                # -> 1.25
  #
  def + (a)
    if a.kind_of?(Rational)
      num = @numerator * a.denominator
      num_a = a.numerator * @denominator
      Rational(num + num_a, @denominator * a.denominator)
    elsif a.kind_of?(Integer)
      self + Rational.new!(a, 1)
    elsif a.kind_of?(Float)
      Float(self) + a
    else
      x, y = a.coerce(self)
      x + y
    end
  end

  #
  # Returns the difference of this value and +a+.
  # subtracted.
  #
  # Examples:
  #   r = Rational(3,4)    # -> Rational(3,4)
  #   r - 1                # -> Rational(-1,4)
  #   r - 0.5              # -> 0.25
  #
  def - (a)
    if a.kind_of?(Rational)
      num = @numerator * a.denominator
      num_a = a.numerator * @denominator
      Rational(num - num_a, @denominator*a.denominator)
    elsif a.kind_of?(Integer)
      self - Rational.new!(a, 1)
    elsif a.kind_of?(Float)
      Float(self) - a
    else
      x, y = a.coerce(self)
      x - y
    end
  end

  #
  # Returns the product of this value and +a+.
  #
  # Examples:
  #   r = Rational(3,4)    # -> Rational(3,4)
  #   r * 2                # -> Rational(3,2)
  #   r * 4                # -> Rational(3,1)
  #   r * 0.5              # -> 0.375
  #   r * Rational(1,2)    # -> Rational(3,8)
  #
  def * (a)
    if a.kind_of?(Rational)
      num = @numerator * a.numerator
      den = @denominator * a.denominator
      Rational(num, den)
    elsif a.kind_of?(Integer)
      self * Rational.new!(a, 1)
    elsif a.kind_of?(Float)
      Float(self) * a
    else
      x, y = a.coerce(self)
      x * y
    end
  end

  #
  # Returns the quotient of this value and +a+.
  #   r = Rational(3,4)    # -> Rational(3,4)
  #   r / 2                # -> Rational(3,8)
  #   r / 2.0              # -> 0.375
  #   r / Rational(1,2)    # -> Rational(3,2)
  #
  def / (a)
    if a.kind_of?(Rational)
      num = @numerator * a.denominator
      den = @denominator * a.numerator
      Rational(num, den)
    elsif a.kind_of?(Integer)
      raise ZeroDivisionError, "division by zero" if a == 0
      self / Rational.new!(a, 1)
    elsif a.kind_of?(Float)
      Float(self) / a
    else
      x, y = a.coerce(self)
      x / y
    end
  end

  #
  # Returns this value raised to the given power.
  #
  # Examples:
  #   r = Rational(3,4)    # -> Rational(3,4)
  #   r ** 2               # -> Rational(9,16)
  #   r ** 2.0             # -> 0.5625
  #   r ** Rational(1,2)   # -> 0.866025403784439
  #
  def ** (other)
    if other.kind_of?(Rational)
      Float(self) ** other
    elsif other.kind_of?(Integer)
      if other > 0
	num = @numerator ** other
	den = @denominator ** other
      elsif other < 0
	num = @denominator ** -other
	den = @numerator ** -other
      elsif other == 0
	num = 1
	den = 1
      end
      Rational.new!(num, den)
    elsif other.kind_of?(Float)
      Float(self) ** other
    else
      x, y = other.coerce(self)
      x ** y
    end
  end

  def div(other)
    (self / other).floor
  end

  #
  # Returns the remainder when this value is divided by +other+.
  #
  # Examples:
  #   r = Rational(7,4)    # -> Rational(7,4)
  #   r % Rational(1,2)    # -> Rational(1,4)
  #   r % 1                # -> Rational(3,4)
  #   r % Rational(1,7)    # -> Rational(1,28)
  #   r % 0.26             # -> 0.19
  #
  def % (other)
    value = (self / other).floor
    return self - other * value
  end

  #
  # Returns the quotient _and_ remainder.
  #
  # Examples:
  #   r = Rational(7,4)        # -> Rational(7,4)
  #   r.divmod Rational(1,2)   # -> [3, Rational(1,4)]
  #
  def divmod(other)
    value = (self / other).floor
    return value, self - other * value
  end

  #
  # Returns the absolute value.
  #
  def abs
    if @numerator > 0
      self
    else
      Rational.new!(-@numerator, @denominator)
    end
  end

  #
  # Returns +true+ iff this value is numerically equal to +other+.
  #
  # But beware:
  #   Rational(1,2) == Rational(4,8)          # -> true
  #   Rational(1,2) == Rational.new!(4,8)     # -> false
  #
  # Don't use Rational.new!
  #
  def == (other)
    if other.kind_of?(Rational)
      @numerator == other.numerator and @denominator == other.denominator
    elsif other.kind_of?(Integer)
      self == Rational.new!(other, 1)
    elsif other.kind_of?(Float)
      Float(self) == other
    else
      other == self
    end
  end

  #
  # Standard comparison operator.
  #
  def <=> (other)
    if other.kind_of?(Rational)
      num = @numerator * other.denominator
      num_a = other.numerator * @denominator
      v = num - num_a
      if v > 0
	return 1
      elsif v < 0
	return  -1
      else
	return 0
      end
    elsif other.kind_of?(Integer)
      return self <=> Rational.new!(other, 1)
    elsif other.kind_of?(Float)
      return Float(self) <=> other
    elsif defined? other.coerce
      x, y = other.coerce(self)
      return x <=> y
    else
      return nil
    end
  end

  def coerce(other)
    if other.kind_of?(Float)
      return other, self.to_f
    elsif other.kind_of?(Integer)
      return Rational.new!(other, 1), self
    else
      super
    end
  end

  #
  # Converts the rational to an Integer.  Not the _nearest_ integer, the
  # truncated integer.  Study the following example carefully:
  #   Rational(+7,4).to_i             # -> 1
  #   Rational(-7,4).to_i             # -> -1
  #   (-1.75).to_i                    # -> -1
  #
  # In other words:
  #   Rational(-7,4) == -1.75                 # -> true
  #   Rational(-7,4).to_i == (-1.75).to_i     # -> true
  #


  def floor()
    @numerator.div(@denominator)
  end

  def ceil()
    -((-@numerator).div(@denominator))
  end

  def truncate()
    if @numerator < 0
      return -((-@numerator).div(@denominator))
    end
    @numerator.div(@denominator)
  end

  alias_method :to_i, :truncate

  def round()
    if @numerator < 0
      num = -@numerator
      num = num * 2 + @denominator
      den = @denominator * 2
      -(num.div(den))
    else
      num = @numerator * 2 + @denominator
      den = @denominator * 2
      num.div(den)
    end
  end

  #
  # Converts the rational to a Float.
  #
  def to_f
    @numerator.fdiv(@denominator)
  end

  #
  # Returns a string representation of the rational number.
  #
  # Example:
  #   Rational(3,4).to_s          #  "3/4"
  #   Rational(8).to_s            #  "8"
  #
  def to_s
    if @denominator == 1
      @numerator.to_s
    else
      @numerator.to_s+"/"+@denominator.to_s
    end
  end

  #
  # Returns +self+.
  #
  def to_r
    self
  end

  #
  # Returns a reconstructable string representation:
  #
  #   Rational(5,8).inspect     # -> "Rational(5, 8)"
  #
  def inspect
    sprintf("Rational(%s, %s)", @numerator.inspect, @denominator.inspect)
  end

  #
  # Returns a hash code for the object.
  #
  def hash
    @numerator.hash ^ @denominator.hash
  end

  attr :numerator
  attr :denominator

  private :initialize
end

class Integer
  #
  # In an integer, the value _is_ the numerator of its rational equivalent.
  # Therefore, this method returns +self+.
  #
  def numerator
    self
  end

  #
  # In an integer, the denominator is 1.  Therefore, this method returns 1.
  #
  def denominator
    1
  end

  #
  # Returns a Rational representation of this integer.
  #
  def to_r
    Rational(self, 1)
  end

  #
  # Returns the <em>greatest common denominator</em> of the two numbers (+self+
  # and +n+).
  #
  # Examples:
  #   72.gcd 168           # -> 24
  #   19.gcd 36            # -> 1
  #
  # The result is positive, no matter the sign of the arguments.
  #
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

  #
  # Returns the <em>lowest common multiple</em> (LCM) of the two arguments
  # (+self+ and +other+).
  #
  # Examples:
  #   6.lcm 7        # -> 42
  #   6.lcm 9        # -> 18
  #
  def lcm(other)
    if self.zero? or other.zero?
      0
    else
      (self.div(self.gcd(other)) * other).abs
    end
  end

  #
  # Returns the GCD _and_ the LCM (see #gcd and #lcm) of the two arguments
  # (+self+ and +other+).  This is more efficient than calculating them
  # separately.
  #
  # Example:
  #   6.gcdlcm 9     # -> [3, 18]
  #
  def gcdlcm(other)
    gcd = self.gcd(other)
    if self.zero? or other.zero?
      [gcd, 0]
    else
      [gcd, (self.div(gcd) * other).abs]
    end
  end
end

class Fixnum
  remove_method :quo

  # If Rational is defined, returns a Rational number instead of a Float.
  def quo(other)
    Rational.new!(self, 1) / other
  end
  alias rdiv quo

  # Returns a Rational number if the result is in fact rational (i.e. +other+ < 0).
  def rpower (other)
    if other >= 0
      self.power!(other)
    else
      Rational.new!(self, 1)**other
    end
  end

end

class Bignum
  remove_method :quo

  # If Rational is defined, returns a Rational number instead of a Float.
  def quo(other)
    Rational.new!(self, 1) / other
  end
  alias rdiv quo

  # Returns a Rational number if the result is in fact rational (i.e. +other+ < 0).
  def rpower (other)
    if other >= 0
      self.power!(other)
    else
      Rational.new!(self, 1)**other
    end
  end

end

unless defined? 1.power!
  class Fixnum
    alias power! **
    alias ** rpower
  end
  class Bignum
    alias power! **
    alias ** rpower
  end
end
