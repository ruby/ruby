# frozen_string_literal: false
#
#--
# bigdecimal/util extends various native classes to provide the #to_d method,
# and provides BigDecimal#to_d and BigDecimal#to_digits.
#++


class Integer < Numeric
  # call-seq:
  #     int.to_d  -> bigdecimal
  #
  # Returns the value of +int+ as a BigDecimal.
  #
  #     require 'bigdecimal'
  #     require 'bigdecimal/util'
  #
  #     42.to_d   # => 0.42e2
  #
  # See also BigDecimal::new.
  #
  def to_d
    BigDecimal(self)
  end
end


class Float < Numeric
  # call-seq:
  #     float.to_d             -> bigdecimal
  #     float.to_d(precision)  -> bigdecimal
  #
  # Returns the value of +float+ as a BigDecimal.
  # The +precision+ parameter is used to determine the number of
  # significant digits for the result (the default is Float::DIG).
  #
  #     require 'bigdecimal'
  #     require 'bigdecimal/util'
  #
  #     0.5.to_d         # => 0.5e0
  #     1.234.to_d(2)    # => 0.12e1
  #
  # See also BigDecimal::new.
  #
  def to_d(precision=nil)
    BigDecimal(self, precision || Float::DIG)
  end
end


class String
  # call-seq:
  #     str.to_d  -> bigdecimal
  #
  # Returns the result of interpreting leading characters in +str+
  # as a BigDecimal.
  #
  #     require 'bigdecimal'
  #     require 'bigdecimal/util'
  #
  #     "0.5".to_d             # => 0.5e0
  #     "123.45e1".to_d        # => 0.12345e4
  #     "45.67 degrees".to_d   # => 0.4567e2
  #
  # See also BigDecimal::new.
  #
  def to_d
    begin
      BigDecimal(self)
    rescue ArgumentError
      BigDecimal(0)
    end
  end
end


class BigDecimal < Numeric
  # call-seq:
  #     a.to_digits -> string
  #
  # Converts a BigDecimal to a String of the form "nnnnnn.mmm".
  # This method is deprecated; use BigDecimal#to_s("F") instead.
  #
  #     require 'bigdecimal/util'
  #
  #     d = BigDecimal("3.14")
  #     d.to_digits                  # => "3.14"
  #
  def to_digits
    if self.nan? || self.infinite? || self.zero?
      self.to_s
    else
      i       = self.to_i.to_s
      _,f,_,z = self.frac.split
      i + "." + ("0"*(-z)) + f
    end
  end

  # call-seq:
  #     a.to_d -> bigdecimal
  #
  # Returns self.
  #
  #     require 'bigdecimal/util'
  #
  #     d = BigDecimal("3.14")
  #     d.to_d                       # => 0.314e1
  #
  def to_d
    self
  end
end


class Rational < Numeric
  # call-seq:
  #     rat.to_d(precision)  -> bigdecimal
  #
  # Returns the value as a BigDecimal.
  #
  # The required +precision+ parameter is used to determine the number of
  # significant digits for the result.
  #
  #     require 'bigdecimal'
  #     require 'bigdecimal/util'
  #
  #     Rational(22, 7).to_d(3)   # => 0.314e1
  #
  # See also BigDecimal::new.
  #
  def to_d(precision)
    BigDecimal(self, precision)
  end
end
