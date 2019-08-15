class BeTrueMatcher
  def matches?(actual)
    @actual = actual
    @actual == true
  end

  def failure_message
    ["Expected #{@actual.inspect}", "to be true"]
  end

  def negative_failure_message
    ["Expected #{@actual.inspect}", "not to be true"]
  end
end

module MSpecMatchers
  private def be_true
    BeTrueMatcher.new
  end
end
