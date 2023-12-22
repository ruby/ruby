# frozen_string_literal: true
require 'test/unit'

class Test_Load_stringify_symbols < Test::Unit::TestCase
  def test_load_stringify_symbol_required_extensions
    require '-test-/load/stringify_symbols'
    require '-test-/load/stringify_target'
    r1 = StringifySymbols.stringify_symbol("-test-/load/stringify_target", "stt_any_method")
    assert_not_nil r1
    r2 = StringifySymbols.stringify_symbol("-test-/load/stringify_target.so", "stt_any_method")
    assert_equal r1, r2, "resolved symbols should be equal even with or without .so suffix"
  end

  def test_load_stringify_symbol_statically_linked
    require '-test-/load/stringify_symbols'
    # "complex.so" is actually not a statically linked extension.
    # But it is registered in $LOADED_FEATURES, so it can be a target of this test.
    r1 = StringifySymbols.stringify_symbol("complex", "rb_complex_minus")
    assert_not_nil r1
    r2 = StringifySymbols.stringify_symbol("complex.so", "rb_complex_minus")
    assert_equal r1, r2
  end

  def test_load_stringify_symbol_missing_target
    require '-test-/load/stringify_symbols'
    r1 = assert_nothing_raised {
      StringifySymbols.stringify_symbol("something_missing", "unknown_method")
    }
    assert_nil r1
    r2 = assert_nothing_raised {
      StringifySymbols.stringify_symbol("complex.so", "unknown_method")
    }
    assert_nil r2
  end
end
