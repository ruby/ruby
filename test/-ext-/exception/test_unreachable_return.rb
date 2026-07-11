# frozen_string_literal: false
require 'test/unit'
require '-test-/exception'

module Bug
  class Test_UnreachableReturn < Test::Unit::TestCase
    def test_empty_argument
      assert_raise_with_message(RuntimeError, "unreachable_return") {
        Bug::Exception.unreachable_return
      }
    end
  end
end
