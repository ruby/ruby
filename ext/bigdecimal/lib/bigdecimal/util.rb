#
# BigDecimal utility library.
# ----------------------------------------------------------------------
# Contents:
#
#   String#
#     to_d      ... to BigDecimal
#
#   Float#
#     to_d      ... to BigDecimal
#
#   BigDecimal#
#     to_r      ... to Rational
#
#   Rational#
#     to_d      ... to BigDecimal
#
# ----------------------------------------------------------------------
#
class Float < Numeric
  def to_d
    BigDecimal(self.to_s)
  end
end

class String
  def to_d
    BigDecimal(self)
  end
end

class BigDecimal < Numeric
  # to "nnnnnn.mmm" form digit string
  # Use BigDecimal#to_s("F") instead.
  def to_digits
     if self.nan? || self.infinite? || self.zero?
        self.to_s
     else
       i       = self.to_i.to_s
       s,f,y,z = self.frac.split
       i + "." + ("0"*(-z)) + f
     end
  end

  # Convert BigDecimal to Rational
  def to_r 
     sign,digits,base,power = self.split
     numerator = sign*digits.to_i
     denomi_power = power - digits.size # base is always 10
     if denomi_power < 0
        denominator = base ** (-denomi_power)
     else
        denominator = base ** denomi_power
     end
     Rational(numerator,denominator)
  end
end

class Rational < Numeric
  # Convert Rational to BigDecimal
  def to_d(nFig=0)
     num = self.numerator.to_s
     if nFig<=0
        nFig = BigDecimal.double_fig*2+1
     end
     BigDecimal.new(num).div(self.denominator,nFig)
  end
end
