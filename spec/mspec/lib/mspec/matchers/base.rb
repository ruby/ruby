require 'mspec/utils/deprecate'

module MSpecMatchers
end

class MSpecEnv
  include MSpecMatchers
end

# Expectations are sometimes used in a module body
class Module
  include MSpecMatchers
end

class SpecPositiveOperatorMatcher < BasicObject
  def initialize(actual)
    @actual = actual
  end

  def ==(expected)
    result = @actual == expected
    unless result
      ::SpecExpectation.fail_single_arg_predicate(@actual, :==, expected, result, "to be truthy")
    end
  end

  def !=(expected)
    result = @actual != expected
    unless result
      ::SpecExpectation.fail_single_arg_predicate(@actual, :!=, expected, result, "to be truthy")
    end
  end

  def equal?(expected)
    result = @actual.equal?(expected)
    unless result
      ::SpecExpectation.fail_single_arg_predicate(@actual, :equal?, expected, result, "to be truthy")
    end
  end

  def raise(exception = ::Exception, message = nil, options = nil, &block)
    matcher = ::RaiseErrorMatcher.new(exception, message, options, &block)
    unless matcher.matches? @actual
      expected, actual = matcher.failure_message
      ::SpecExpectation.fail_with(expected, actual)
    end
  end

  def method_missing(name, *args, &block)
    result = @actual.__send__(name, *args, &block)
    unless result
      ::SpecExpectation.fail_predicate(@actual, name, args, block, result, "to be truthy")
    end
  end
end

class SpecNegativeOperatorMatcher < BasicObject
  def initialize(actual)
    @actual = actual
  end

  def ==(expected)
    result = @actual == expected
    if result
      ::SpecExpectation.fail_single_arg_predicate(@actual, :==, expected, result, "to be falsy")
    end
  end

  def !=(expected)
    result = @actual != expected
    if result
      ::SpecExpectation.fail_single_arg_predicate(@actual, :!=, expected, result, "to be falsy")
    end
  end

  def equal?(expected)
    result = @actual.equal?(expected)
    if result
      ::SpecExpectation.fail_single_arg_predicate(@actual, :equal?, expected, result, "to be falsy")
    end
  end

  def raise(exception = ::Exception, message = nil, options = nil, &block)
    matcher = ::RaiseErrorMatcher.new(exception, message, options, &block)
    if matcher.matches? @actual
      expected, actual = matcher.negative_failure_message
      ::SpecExpectation.fail_with(expected, actual)
    end
  end

  def method_missing(name, *args, &block)
    result = @actual.__send__(name, *args, &block)
    if result
      ::SpecExpectation.fail_predicate(@actual, name, args, block, result, "to be falsy")
    end
  end
end
