# frozen_string_literal: false
require 'test/unit'

class TestRedefinition < Test::Unit::TestCase
  def test_redefinition
    message = %r[test/unit: method TestForTestRedefinition#test_redefinition is redefined$]
    assert_raise_with_message(Test::Unit::AssertionFailedError, message) do
      require_relative("test4test_redefinition.rb")
    end
  end
end
