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
    method_missing(:==, expected)
  end

  def !=(expected)
    method_missing(:!=, expected)
  end

  def equal?(expected)
    method_missing(:equal?, expected)
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
    method_missing(:==, expected)
  end

  def !=(expected)
    method_missing(:!=, expected)
  end

  def equal?(expected)
    method_missing(:equal?, expected)
  end

  def method_missing(name, *args, &block)
    result = @actual.__send__(name, *args, &block)
    if result
      ::SpecExpectation.fail_predicate(@actual, name, args, block, result, "to be falsy")
    end
  end
end
