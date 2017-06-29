class RespondToMatcher
  def initialize(expected)
    @expected = expected
  end

  def matches?(actual)
    @actual = actual
    @actual.respond_to?(@expected)
  end

  def failure_message
    ["Expected #{@actual.inspect} (#{@actual.class})", "to respond to #{@expected}"]
  end

  def negative_failure_message
    ["Expected #{@actual.inspect} (#{@actual.class})", "not to respond to #{@expected}"]
  end
end

module MSpecMatchers
  private def respond_to(expected)
    RespondToMatcher.new(expected)
  end
end
