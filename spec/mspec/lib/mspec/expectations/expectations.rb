class SpecExpectationNotMetError < StandardError
end

class SpecExpectationNotFoundError < StandardError
  def message
    "No behavior expectation was found in the example"
  end
end

class SkippedSpecError < StandardError
end

class SpecExpectation
  def self.fail_with(expected, actual)
    expected_to_s = expected.to_s
    actual_to_s = actual.to_s
    if expected_to_s.size + actual_to_s.size > 80
      message = "#{expected_to_s}\n#{actual_to_s}"
    else
      message = "#{expected_to_s} #{actual_to_s}"
    end
    raise SpecExpectationNotMetError, message
  end

  def self.fail_predicate(receiver, predicate, args, block, result, expectation)
    receiver_to_s = MSpec.format(receiver)
    before_method = predicate.to_s =~ /^[a-z]/ ? "." : " "
    predicate_to_s = "#{before_method}#{predicate}"
    predicate_to_s += " " unless args.empty?
    args_to_s = args.map { |arg| MSpec.format(arg) }.join(', ')
    args_to_s += " { ... }" if block
    result_to_s = MSpec.format(result)
    raise SpecExpectationNotMetError, "Expected #{receiver_to_s}#{predicate_to_s}#{args_to_s}\n#{expectation} but was #{result_to_s}"
  end
end
