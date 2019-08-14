class BeAnInstanceOfMatcher
  def initialize(expected)
    @expected = expected
  end

  def matches?(actual)
    @actual = actual
    @actual.instance_of?(@expected)
  end

  def failure_message
    ["Expected #{@actual.inspect} (#{@actual.class})",
     "to be an instance of #{@expected}"]
  end

  def negative_failure_message
    ["Expected #{@actual.inspect} (#{@actual.class})",
     "not to be an instance of #{@expected}"]
  end
end

module MSpecMatchers
  private def be_an_instance_of(expected)
    BeAnInstanceOfMatcher.new(expected)
  end
end
