# frozen_string_literal: true

# Here we are reopening the prism module to provide methods on nodes that aren't
# templated and are meant as convenience methods.
module Prism
  class FloatNode < Node
    # Returns the value of the node as a Ruby Float.
    def value
      Float(slice)
    end
  end

  class ImaginaryNode < Node
    # Returns the value of the node as a Ruby Complex.
    def value
      Complex(0, numeric.value)
    end
  end

  class IntegerNode < Node
    # Returns the value of the node as a Ruby Integer.
    def value
      Integer(slice)
    end
  end

  class InterpolatedRegularExpressionNode < Node
    # Returns a numeric value that represents the flags that were used to create
    # the regular expression.
    def options
      o = flags & (RegularExpressionFlags::IGNORE_CASE | RegularExpressionFlags::EXTENDED | RegularExpressionFlags::MULTI_LINE)
      o |= Regexp::FIXEDENCODING if flags.anybits?(RegularExpressionFlags::EUC_JP | RegularExpressionFlags::WINDOWS_31J | RegularExpressionFlags::UTF_8)
      o |= Regexp::NOENCODING if flags.anybits?(RegularExpressionFlags::ASCII_8BIT)
      o
    end
  end

  class RationalNode < Node
    # Returns the value of the node as a Ruby Rational.
    def value
      Rational(slice.chomp("r"))
    end
  end

  class RegularExpressionNode < Node
    # Returns a numeric value that represents the flags that were used to create
    # the regular expression.
    def options
      o = flags & (RegularExpressionFlags::IGNORE_CASE | RegularExpressionFlags::EXTENDED | RegularExpressionFlags::MULTI_LINE)
      o |= Regexp::FIXEDENCODING if flags.anybits?(RegularExpressionFlags::EUC_JP | RegularExpressionFlags::WINDOWS_31J | RegularExpressionFlags::UTF_8)
      o |= Regexp::NOENCODING if flags.anybits?(RegularExpressionFlags::ASCII_8BIT)
      o
    end
  end
end
