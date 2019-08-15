class BeKindOfMatcher
  def initialize(expected)
    @expected = expected
  end

  def matches?(actual)
    @actual = actual
    @actual.is_a?(@expected)
  end

  def failure_message
    ["Expected #{@actual.inspect} (#{@actual.class})", "to be kind of #{@expected}"]
  end

  def negative_failure_message
    ["Expected #{@actual.inspect} (#{@actual.class})", "not to be kind of #{@expected}"]
  end
end

module MSpecMatchers
  private def be_kind_of(expected)
    BeKindOfMatcher.new(expected)
  end
end
