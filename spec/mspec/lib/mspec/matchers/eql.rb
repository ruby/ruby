class EqlMatcher
  def initialize(expected)
    @expected = expected
  end

  def matches?(actual)
    @actual = actual
    @actual.eql?(@expected)
  end

  def failure_message
    ["Expected #{MSpec.format(@actual)}",
     "to have same value and type as #{MSpec.format(@expected)}"]
  end

  def negative_failure_message
    ["Expected #{MSpec.format(@actual)}",
     "not to have same value or type as #{MSpec.format(@expected)}"]
  end
end

module MSpecMatchers
  private def eql(expected)
    EqlMatcher.new(expected)
  end
end
