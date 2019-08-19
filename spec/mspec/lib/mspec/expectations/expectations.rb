class SpecExpectationNotMetError < StandardError
end

class SpecExpectationNotFoundError < StandardError
  def message
    "No behavior expectation was found in the example"
  end
end

class SpecExpectation
  def self.fail_with(expected, actual)
    expected_to_s = expected.to_s
    actual_to_s = actual.to_s
    if expected_to_s.size + actual_to_s.size > 80
      message = "#{expected_to_s.chomp}\n#{actual_to_s}"
    else
      message = "#{expected_to_s} #{actual_to_s}"
    end
    Kernel.raise SpecExpectationNotMetError, message
  end
end
