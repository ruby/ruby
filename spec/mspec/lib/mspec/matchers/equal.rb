class EqualMatcher
  def initialize(expected)
    @expected = expected
  end

  def matches?(actual)
    @actual = actual
    @actual.equal?(@expected)
  end

  def failure_message
    ["Expected #{@actual.pretty_inspect}",
     "to be identical to #{@expected.pretty_inspect}"]
  end

  def negative_failure_message
    ["Expected #{@actual.pretty_inspect}",
     "not to be identical to #{@expected.pretty_inspect}"]
  end
end

module MSpecMatchers
  private def equal(expected)
    EqualMatcher.new(expected)
  end
end
