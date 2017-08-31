class BeNilMatcher
  def matches?(actual)
    @actual = actual
    @actual.nil?
  end

  def failure_message
    ["Expected #{@actual.inspect}", "to be nil"]
  end

  def negative_failure_message
    ["Expected #{@actual.inspect}", "not to be nil"]
  end
end

module MSpecMatchers
  private def be_nil
    BeNilMatcher.new
  end
end
