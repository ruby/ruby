TOLERANCE = 0.00003 unless Object.const_defined?(:TOLERANCE)

class BeCloseMatcher
  def initialize(expected, tolerance)
    @expected = expected
    @tolerance = tolerance
  end

  def matches?(actual)
    @actual = actual
    (@actual - @expected).abs <= @tolerance
  end

  def failure_message
    ["Expected #{@actual}", "to be within #{@expected} +/- #{@tolerance}"]
  end

  def negative_failure_message
    ["Expected #{@actual}", "not to be within #{@expected} +/- #{@tolerance}"]
  end
end

module MSpecMatchers
  private def be_close(expected, tolerance)
    BeCloseMatcher.new(expected, tolerance)
  end
end
