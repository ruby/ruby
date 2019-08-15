class BeTrueOrFalseMatcher
  def matches?(actual)
    @actual = actual
    @actual == true || @actual == false
  end

  def failure_message
    ["Expected #{@actual.inspect}", "to be true or false"]
  end

  def negative_failure_message
    ["Expected #{@actual.inspect}", "not to be true or false"]
  end
end

module MSpecMatchers
  private def be_true_or_false
    BeTrueOrFalseMatcher.new
  end
end
