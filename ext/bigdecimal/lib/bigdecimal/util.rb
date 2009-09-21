#
# BigDecimal utility library.
#
# To use these functions, require 'bigdecimal/util'
#
# The following methods are provided to convert other types to BigDecimals:
#
#   String#to_d -> BigDecimal
#   Float#to_d -> BigDecimal
#   Rational#to_d -> BigDecimal
#
# The following method is provided to convert BigDecimals to other types:
#
#   BigDecimal#to_r -> Rational
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
  # Converts a BigDecimal to a String of the form "nnnnnn.mmm".
  # This method is deprecated; use BigDecimal#to_s("F") instead.
  def to_digits
    if self.nan? || self.infinite? || self.zero?
      self.to_s
    else
      i       = self.to_i.to_s
      s,f,y,z = self.frac.split
      i + "." + ("0"*(-z)) + f
    end
  end
end

class Rational < Numeric
  # Converts a Rational to a BigDecimal
  def to_d(nFig=0)
    num = self.numerator.to_s
    if nFig<=0
      nFig = BigDecimal.double_fig*2+1
    end
    BigDecimal.new(num).div(self.denominator,nFig)
  end
end
