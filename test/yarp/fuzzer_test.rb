# frozen_string_literal: true

require_relative "test_helper"

# These tests are simply to exercise snippets found by the fuzzer that caused invalid memory access.
class FuzzerTest < Test::Unit::TestCase
  class << self
    def snippet(name, source)
      test "fuzzer #{name}" do
        YARP.dump(source)
      end
    end
  end

  snippet "incomplete global variable", "$"
  snippet "incomplete symbol", ":"
  snippet "incomplete escaped string", '"\\'
end
