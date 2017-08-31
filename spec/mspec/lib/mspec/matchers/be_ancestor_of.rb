class BeAncestorOfMatcher
  def initialize(expected)
    @expected = expected
  end

  def matches?(actual)
    @actual = actual
    @expected.ancestors.include? @actual
  end

  def failure_message
    ["Expected #{@actual}", "to be an ancestor of #{@expected}"]
  end

  def negative_failure_message
    ["Expected #{@actual}", "not to be an ancestor of #{@expected}"]
  end
end

module MSpecMatchers
  private def be_ancestor_of(expected)
    BeAncestorOfMatcher.new(expected)
  end
end
