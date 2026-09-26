# frozen_string_literal: false
require_relative 'base'

class TestMkmfTryConstant < TestMkmf
  def test_simple
    assert_equal( 0, mkmf {try_constant("0")}, MKMFLOG)
    assert_equal( 1, mkmf {try_constant("1")}, MKMFLOG)
    assert_equal(-1, mkmf {try_constant("-1")}, MKMFLOG)
  end

  def test_sizeof
    assert_equal(config_value("SIZEOF_INT").to_i, mkmf {try_constant("sizeof(int)")}, MKMFLOG)
    assert_equal(config_value("SIZEOF_LONG").to_i, mkmf {try_constant("sizeof(long)")}, MKMFLOG)
    assert_equal(config_value("SIZEOF_VOIDP").to_i, mkmf {try_constant("sizeof(void*)")}, MKMFLOG)
    assert_equal(config_value("SIZEOF_VALUE").to_i, mkmf {try_constant("sizeof(Qnil)")}, MKMFLOG)
  end

  def test_long
    sizeof_int = config_value("SIZEOF_INT").to_i
    sizeof_long = config_value("SIZEOF_LONG").to_i
    if sizeof_long > sizeof_int
      type = 'long'
    else
      sizeof_long_long = config_value("SIZEOF_LONG_LONG").to_i
      return if !sizeof_long_long or sizeof_long_long <= sizeof_int
      type = 'LONG_LONG'
    end

    decl = "#define CONFTEST_VALUE (unsigned #{type})(((unsigned #{type})1)<<(CHAR_BIT*sizeof(int)))"
    assert_operator(mkmf {try_constant("CONFTEST_VALUE", [[decl]])}, :>, 0, MKMFLOG)
  end

  def test_large_unsigned
    assert_operator(mkmf {try_constant("1U<<(CHAR_BIT*sizeof(int)-1)")}, :>, 0, MKMFLOG)
  end
end
