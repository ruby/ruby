#
#   rational.rb - 
#   	$Release Version: 0.5 $
#   	$Revision: 1.7 $
#   	$Date: 1999/08/24 12:49:28 $
#   	by Keiju ISHITSUKA(SHL Japan Inc.)
#
# --
#   Usage:
#   class Rational < Numeric
#      (include Comparable)
#
#   Rational(a, b) --> a/b
#
#   Rational::+
#   Rational::-
#   Rational::*
#   Rational::/
#   Rational::**
#   Rational::%
#   Rational::divmod
#   Rational::abs
#   Rational::<=>
#   Rational::to_i
#   Rational::to_f
#   Rational::to_s
#
#   Integer::gcd
#   Integer::lcm
#   Integer::gcdlcm
#   Integer::to_r
#
#   Fixnum::**
#   Fixnum::quo
#   Bignum::**
#   Bignum::quo
#

def Rational(a, b = 1)
  if a.kind_of?(Rational) && b == 1
    a
  else
    Rational.reduce(a, b)
  end
end
  
class Rational < Numeric
  @RCS_ID='-$Id: rational.rb,v 1.7 1999/08/24 12:49:28 keiju Exp keiju $-'

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
  
  def Rational.new!(num, den = 1)
    new(num, den)
  end

  private_class_method :new

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
  
  def % (other)
    value = (self / other).to_i
    return self - other * value
  end
  
  def divmod(other)
    value = (self / other).to_i
    return value, self - other * value
  end
  
  def abs
    if @numerator > 0
      Rational.new!(@numerator, @denominator)
    else
      Rational.new!(-@numerator, @denominator)
    end
  end

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

  def to_i
    Integer(@numerator.div(@denominator))
  end
  
  def to_f
    @numerator.to_f/@denominator.to_f
  end
  
  def to_s
    if @denominator == 1
      @numerator.to_s
    else
      @numerator.to_s+"/"+@denominator.to_s
    end
  end
  
  def to_r
    self
  end
  
  def inspect
    sprintf("Rational(%s, %s)", @numerator.inspect, @denominator.inspect)
  end
  
  def hash
    @numerator.hash ^ @denominator.hash
  end
  
  attr :numerator
  attr :denominator
  
  private :initialize
end

class Integer
  def numerator
    self
  end
  
  def denominator
    1
  end
  
  def to_r
    Rational(self, 1)
  end
  
  def gcd(n)
    m = self.abs
    n = n.abs

    return n if m == 0
    return m if n == 0

    b = 0
    while n[0] == 0 && m[0] == 0
      b += 1; n >>= 1; m >>= 1
    end
    m >>= 1 while m[0] == 0
    n >>= 1 while n[0] == 0
    while m != n
      m, n = n, m if n > m
      m -= n; m >>= 1 while m[0] == 0
    end
    m << b
  end
  
  def gcd2(int)
    a = self.abs
    b = int.abs
  
    a, b = b, a if a < b
  
    while b != 0
      void, a = a.divmod(b)
      a, b = b, a
    end
    return a
  end

  def lcm(int)
    a = self.abs
    b = int.abs
    gcd = a.gcd(b)
    (a.div(gcd)) * b
  end
  
  def gcdlcm(int)
    a = self.abs
    b = int.abs
    gcd = a.gcd(b)
    return gcd, (a.div(gcd)) * b
  end
  
end

class Fixnum
  undef quo
  def quo(other)
    Rational.new!(self,1) / other
  end
  alias rdiv quo
  
  def rpower (other)
    if other >= 0
      self.power!(other)
    else
      Rational.new!(self,1)**other
    end
  end

  unless defined? 1.power!
    alias power! ** 
    alias ** rpower
  end
end

class Bignum
  unless defined? Complex
    alias power! **
  end

  undef quo
  def quo(other)
    Rational.new!(self,1) / other
  end
  alias rdiv quo
  
  def rpower (other)
    if other >= 0
      self.power!(other)
    else
      Rational.new!(self, 1)**other
    end
  end
  
  unless defined? Complex
    alias ** rpower
  end
end
