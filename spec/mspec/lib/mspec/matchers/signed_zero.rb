class SignedZeroMatcher
  def initialize(expected_sign)
    @expected_sign = expected_sign
  end

  def matches?(actual)
    @actual = actual
    (1.0/actual).infinite? == @expected_sign
  end

  def failure_message
    ["Expected #{@actual}", "to be #{"-" if @expected_sign == -1}0.0"]
  end

  def negative_failure_message
    ["Expected #{@actual}", "not to be #{"-" if @expected_sign == -1}0.0"]
  end
end

module MSpecMatchers
  private def be_positive_zero
    SignedZeroMatcher.new(1)
  end

  private def be_negative_zero
    SignedZeroMatcher.new(-1)
  end
end
