#
#   rational.rb - 
#   	$Release Version: 0.5 $
#   	$Revision: 1.3 $
#   	$Date: 1998/03/11 14:09:03 $
#   	by Keiju ISHITSUKA(SHL Japan Inc.)
#
# --
#   Usage:
#   class Rational < Numeric
#      (include Compareable)
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
#   Bignum::**
#   
#

def Rational(a, b = 1)
  if a.kind_of?(Rational) && b == 1
    a
  else
    Rational.reduce(a, b)
  end
end
  
class Rational < Numeric
  @RCS_ID='-$Id: rational.rb,v 1.3 1998/03/11 14:09:03 keiju Exp keiju $-'

  def Rational.reduce(num, den = 1)
    raise ZeroDivisionError, "denometor is 0" if den == 0

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
      x , y = a.coerce(self)
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
      x , y = a.coerce(self)
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
      x , y = a.coerce(self)
      x * y
    end
  end
  
  def / (a)
    if a.kind_of?(Rational)
      num = @numerator * a.denominator
      den = @denominator * a.numerator
      Rational(num, den)
    elsif a.kind_of?(Integer)
      raise ZeroDivisionError, "devided by 0" if a == 0
      self / Rational.new!(a, 1)
    elsif a.kind_of?(Float)
      Float(self) / a
    else
      x , y = a.coerce(self)
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
      x , y = other.coerce(self)
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
    else
      x , y = other.coerce(self)
      return x <=> y
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
  
  def hash
    @numerator ^ @denominator
  end
  
  attr :numerator
  attr :denominator
  
  private :initialize
end

class Integer
  def numerator
    self
  end
  
  def denomerator
    1
  end
  
  def to_r
    Rational(self, 1)
  end
  
  def gcd(int)
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
  alias div! /;
  def div(other)
    if other.kind_of?(Fixnum)
      self.div!(other)
    elsif other.kind_of?(Bignum)
      x, y = other.coerce(self)
      x.div!(y)
    else
      x, y = other.coerce(self)
      x / y
    end
  end
  
#  alias divmod! divmod
  
  if not defined? Complex
    alias power! **;
  end
  
#   def rdiv(other)
#     if other.kind_of?(Fixnum)
#       Rational(self, other)
#     elsif
#       x, y = other.coerce(self)
#       if defined?(x.div())
# 	x.div(y)
#       else
# 	x / y
#       end
#     end
  #   end
  
  def rdiv(other)
    Rational.new!(self,1) / other
  end
  
  def rpower (other)
    if other >= 0
      self.power!(other)
    else
      Rational.new!(self,1)**other
    end
  end
    
  if not defined? Complex
    alias ** rpower
  end
end

class Bignum
  alias div! /;
  alias div /;
  alias divmod! divmod
  
  if not defined? power!
    alias power! **
  end
  
  def rdiv(other)
    Rational.new!(self,1) / other
  end
  
  def rpower (other)
    if other >= 0
      self.power!(other)
    else
      Rational.new!(self, 1)**other
    end
  end
  
  if not defined? Complex
    alias ** rpower
  end
  
end

