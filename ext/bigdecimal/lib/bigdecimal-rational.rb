#
# BigDecimal <-> Rational 
#
class BigDecimal
    # Convert BigDecimal to Rational
    def to_r 
       sign,digits,base,power = self.to_parts
       numerator = sign*digits.to_i
       denomi_power = power - digits.size # base is always 10
       if denomi_power < 0
          denominator = base ** (-denomi_power)
       else
          denominator = base ** denomi_power
       end
       Rational.new(numerator,denominator)
    end
end

class Rational
  # Convert Rational to BigDecimal
  # to_d returns an array [quotient,residue]
  def to_d(nFig=0)
     num = self.numerator.to_s
     if nFig<=0
        nFig = BigDecimal.double_fig*2+1
     end
     BigDecimal.new(num).div(self.denominator,nFig)
  end
end

