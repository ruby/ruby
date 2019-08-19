class BeFalseMatcher
  def matches?(actual)
    @actual = actual
    @actual == false
  end

  def failure_message
    ["Expected #{@actual.inspect}", "to be false"]
  end

  def negative_failure_message
    ["Expected #{@actual.inspect}", "not to be false"]
  end
end

module MSpecMatchers
  private def be_false
    BeFalseMatcher.new
  end
end
