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
#     to_digits ... to xxxxx.yyyy form digit string(not 0.zzzE?? form).
#     to_r      ... to Rational
#
#   Rational#
#     to_d      ... to BigDecimal
#
# ----------------------------------------------------------------------
#
class Float < Numeric
  def to_d
    BigFloat::new(selt.to_s)
  end
end

class String
  def to_d
    BigDecimal::new(self)
  end
end

class BigDecimal < Numeric
  # to "nnnnnn.mmm" form digit string
  def to_digits
     if self.nan? || self.infinite?
        self.to_s
     else
       s,i,y,z = self.fix.split
       s,f,y,z = self.frac.split
       if s > 0
         s = ""
       else
         s = "-"
       end
       s + i + "." + f
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
