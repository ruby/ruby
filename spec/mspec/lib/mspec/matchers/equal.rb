class EqualMatcher
  def initialize(expected)
    @expected = expected
  end

  def matches?(actual)
    @actual = actual
    @actual.equal?(@expected)
  end

  def failure_message
    ["Expected #{MSpec.format(@actual)}",
     "to be identical to #{MSpec.format(@expected)}"]
  end

  def negative_failure_message
    ["Expected #{MSpec.format(@actual)}",
     "not to be identical to #{MSpec.format(@expected)}"]
  end
end

module MSpecMatchers
  private def equal(expected)
    MSpec.deprecate __method__, '.should.equal?'
    EqualMatcher.new(expected)
  end
end
