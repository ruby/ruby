class EqlMatcher
  def initialize(expected)
    @expected = expected
  end

  def matches?(actual)
    @actual = actual
    @actual.eql?(@expected)
  end

  def failure_message
    ["Expected #{@actual.pretty_inspect}",
     "to have same value and type as #{@expected.pretty_inspect}"]
  end

  def negative_failure_message
    ["Expected #{@actual.pretty_inspect}",
     "not to have same value or type as #{@expected.pretty_inspect}"]
  end
end

module MSpecMatchers
  private def eql(expected)
    EqlMatcher.new(expected)
  end
end
