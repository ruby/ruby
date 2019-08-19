class IncludeAnyOfMatcher
  def initialize(*expected)
    @expected = expected
  end

  def matches?(actual)
    @actual = actual
    @expected.each do |e|
      if @actual.include?(e)
        return true
      end
    end
    return false
  end

  def failure_message
    ["Expected #{@actual.inspect}", "to include any of #{@expected.inspect}"]
  end

  def negative_failure_message
    ["Expected #{@actual.inspect}", "not to include any of #{@expected.inspect}"]
  end
end

module MSpecMatchers
  private def include_any_of(*expected)
    IncludeAnyOfMatcher.new(*expected)
  end
end
