class IncludeMatcher
  def initialize(*expected)
    @expected = expected
  end

  def matches?(actual)
    @actual = actual
    @expected.each do |e|
      @element = e
      unless @actual.include?(e)
        return false
      end
    end
    return true
  end

  def failure_message
    ["Expected #{@actual.inspect}", "to include #{@element.inspect}"]
  end

  def negative_failure_message
    ["Expected #{@actual.inspect}", "not to include #{@element.inspect}"]
  end
end

# Cannot override #include at the toplevel in MRI
module MSpecMatchers
  private def include(*expected)
    IncludeMatcher.new(*expected)
  end
end
