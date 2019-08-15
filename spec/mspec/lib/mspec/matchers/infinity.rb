class InfinityMatcher
  def initialize(expected_sign)
    @expected_sign = expected_sign
  end

  def matches?(actual)
    @actual = actual
    @actual.kind_of?(Float) && @actual.infinite? == @expected_sign
  end

  def failure_message
    ["Expected #{@actual}", "to be #{"-" if @expected_sign == -1}Infinity"]
  end

  def negative_failure_message
    ["Expected #{@actual}", "not to be #{"-" if @expected_sign == -1}Infinity"]
  end
end

module MSpecMatchers
  private def be_positive_infinity
    InfinityMatcher.new(1)
  end

  private def be_negative_infinity
    InfinityMatcher.new(-1)
  end
end
