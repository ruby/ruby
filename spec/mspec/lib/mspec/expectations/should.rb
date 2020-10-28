class Object
  NO_MATCHER_GIVEN = Object.new

  def should(matcher = NO_MATCHER_GIVEN)
    MSpec.expectation
    state = MSpec.current.state
    raise "should outside example" unless state
    MSpec.actions :expectation, state

    if NO_MATCHER_GIVEN.equal?(matcher)
      SpecPositiveOperatorMatcher.new(self)
    else
      unless matcher.matches? self
        expected, actual = matcher.failure_message
        SpecExpectation.fail_with(expected, actual)
      end
    end
  end

  def should_not(matcher = NO_MATCHER_GIVEN)
    MSpec.expectation
    state = MSpec.current.state
    raise "should_not outside example" unless state
    MSpec.actions :expectation, state

    if NO_MATCHER_GIVEN.equal?(matcher)
      SpecNegativeOperatorMatcher.new(self)
    else
      if matcher.matches? self
        expected, actual = matcher.negative_failure_message
        SpecExpectation.fail_with(expected, actual)
      end
    end
  end
end
