class Object
  NO_MATCHER_GIVEN = Object.new

  def should(matcher = NO_MATCHER_GIVEN)
    MSpec.expectation
    MSpec.actions :expectation, MSpec.current.state
    unless matcher.equal? NO_MATCHER_GIVEN
      unless matcher.matches? self
        expected, actual = matcher.failure_message
        SpecExpectation.fail_with(expected, actual)
      end
    else
      SpecPositiveOperatorMatcher.new(self)
    end
  end

  def should_not(matcher = NO_MATCHER_GIVEN)
    MSpec.expectation
    MSpec.actions :expectation, MSpec.current.state
    unless matcher.equal? NO_MATCHER_GIVEN
      if matcher.matches? self
        expected, actual = matcher.negative_failure_message
        SpecExpectation.fail_with(expected, actual)
      end
    else
      SpecNegativeOperatorMatcher.new(self)
    end
  end
end
