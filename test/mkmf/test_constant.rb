require_relative 'base'

class TestMkmf
  class TestTryConstant < TestMkmf
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
  end
end
