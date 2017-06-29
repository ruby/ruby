class BeNaNMatcher
  def matches?(actual)
    @actual = actual
    @actual.kind_of?(Float) && @actual.nan?
  end

  def failure_message
    ["Expected #{@actual}", "to be NaN"]
  end

  def negative_failure_message
    ["Expected #{@actual}", "not to be NaN"]
  end
end

module MSpecMatchers
  private def be_nan
    BeNaNMatcher.new
  end
end
