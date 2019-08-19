class BeEmptyMatcher
  def matches?(actual)
    @actual = actual
    @actual.empty?
  end

  def failure_message
    ["Expected #{@actual.inspect}", "to be empty"]
  end

  def negative_failure_message
    ["Expected #{@actual.inspect}", "not to be empty"]
  end
end

module MSpecMatchers
  private def be_empty
    BeEmptyMatcher.new
  end
end
