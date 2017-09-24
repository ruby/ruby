# frozen_string_literal: true
require 'test/unit'
require '-test-/load/protect'

class Test_Load_Protect < Test::Unit::TestCase
  def test_load_protect
    assert_raise(LoadError) {
      Bug.load_protect(__dir__+"/nonexistent.rb")
    }
    assert_raise_with_message(RuntimeError, "foo") {
      Bug.load_protect(__dir__+"/script.rb")
    }
  end
end
