class Object
  NO_MATCHER_GIVEN = Object.new

  def should(matcher = NO_MATCHER_GIVEN, &block)
    MSpec.expectation
    state = MSpec.current.state
    raise "should outside example" unless state
    MSpec.actions :expectation, state

    if NO_MATCHER_GIVEN.equal?(matcher)
      SpecPositiveOperatorMatcher.new(self)
    else
      # The block was given to #should syntactically, but it was intended for a matcher like #raise_error
      matcher.block = block if block

      unless matcher.matches? self
        expected, actual = matcher.failure_message
        SpecExpectation.fail_with(expected, actual)
      end
    end
  end

  def should_not(matcher = NO_MATCHER_GIVEN, &block)
    MSpec.expectation
    state = MSpec.current.state
    raise "should_not outside example" unless state
    MSpec.actions :expectation, state

    if NO_MATCHER_GIVEN.equal?(matcher)
      SpecNegativeOperatorMatcher.new(self)
    else
      # The block was given to #should_not syntactically, but it was intended for the matcher
      matcher.block = block if block

      if matcher.matches? self
        expected, actual = matcher.negative_failure_message
        SpecExpectation.fail_with(expected, actual)
      end
    end
  end
end
