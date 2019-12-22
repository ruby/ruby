# frozen_string_literal: false
require 'test/unit'
require "-test-/struct"

class Bug::Struct::Test_Duplicate < Test::Unit::TestCase
  def test_new_duplicate
    bug12291 = '[ruby-core:74971] [Bug #12291]'
    assert_raise_with_message(ArgumentError, /duplicate member/, bug12291) {
      Bug::Struct.new_duplicate(nil, "a")
    }
    assert_raise_with_message(ArgumentError, /duplicate member/, bug12291) {
      Bug::Struct.new_duplicate("X", "a")
    }
  end

  def test_new_duplicate_under
    bug12291 = '[ruby-core:74971] [Bug #12291]'
    assert_raise_with_message(ArgumentError, /duplicate member/, bug12291) {
      Bug::Struct.new_duplicate_under("x", "a")
    }
  end
end
