module RangeSpecs
  class TenfoldSucc
    include Comparable

    attr_reader :n

    def initialize(n)
      @n = n
    end

    def <=>(other)
      @n <=> other.n
    end

    def succ
      self.class.new(@n * 10)
    end
  end

  # Custom Range classes Xs and Ys
  class Custom
    include Comparable
    attr_reader :length

    def initialize(n)
      @length = n
    end

    def eql?(other)
      inspect.eql? other.inspect
    end
    alias :== :eql?

    def inspect
      'custom'
    end

    def <=>(other)
      @length <=> other.length
    end
  end

  class WithoutSucc
    include Comparable
    attr_reader :n

    def initialize(n)
      @n = n
    end

    def eql?(other)
      inspect.eql? other.inspect
    end
    alias :== :eql?

    def inspect
      "WithoutSucc(#{@n})"
    end

    def <=>(other)
      return nil unless other.is_a?(WithoutSucc)
      @n <=> other.n
    end
  end

  class WithSucc
    attr_reader :value

    def initialize(value)
      @value = value
    end

    def <=>(other)
      return nil unless other.is_a?(WithSucc)
      @value <=> other.value
    end

    def succ
      WithSucc.new(@value + 1)
    end

    def ==(other)
      return false unless other.is_a?(WithSucc)
      @value == other.value
    end
  end

  class Number < Numeric
    attr_reader :value

    def initialize(value)
      @value = value
    end

    def <=>(other)
      return nil unless other.is_a?(Number)
      @value <=> other.value
    end

    def +(other)
      raise "supported Integer only" unless other.is_a?(Integer)
      Number.new(@value + other)
    end

    def ==(other)
      return false unless other.is_a?(Number)
      @value == other.value
    end

    # to prevent type conversion
    undef_method :coerce
  end

  # supports only interface required by Range#cover? + #succ
  class CoverElementWithSucc
    attr_reader :n

    def initialize(n)
      @n = n
    end

    def <=>(other)
      return nil unless other.is_a?(CoverElementWithSucc)
      @n <=> other.n
    end

    def succ
      CoverElementWithSucc.new(@n + 1)
    end

    def inspect
      "CoverElementWithSucc(#{@n})"
    end
  end

  class Xs < Custom # represent a string of 'x's
    def succ
      Xs.new(@length + 1)
    end

    def inspect
      'x' * @length
    end
  end

  class Ys < Custom # represent a string of 'y's
    def succ
      Ys.new(@length + 1)
    end

    def inspect
      'y' * @length
    end
  end

  class MyRange < Range
  end

  class ComparisonError < RuntimeError
  end
end
