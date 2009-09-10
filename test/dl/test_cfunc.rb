require_relative 'test_base'
require 'dl/func'

module DL
  class TestCFunc < TestBase
    def setup
      super
      @name = 'strcpy'
      @cf = CFunc.new(@libc[@name], TYPE_VOIDP, @name)
    end

    def test_new_ptr_type_name
      assert_equal @name, @cf.name
      assert @cf.name.tainted?, 'name should be tainted'
      assert_equal :cdecl, @cf.calltype
      assert_equal TYPE_VOIDP, @cf.ctype
    end

    def test_new_ptr
      cf = CFunc.new(@libc['strcpy'])
      assert_nil cf.name
      assert_equal :cdecl, cf.calltype
      assert_equal TYPE_VOID, cf.ctype
    end

    def test_name_should_be_duped
      assert_equal @name, @cf.name
      assert @cf.name.tainted?, 'name should be tainted'

      name = @name.dup
      @name << 'foo'

      assert_equal name, @cf.name
    end

    def test_to_s
      s = @cf.to_s
      assert s.tainted?, 'to_s should be tainted'
      assert_match(/ptr=#{sprintf("0x%x", @cf.ptr)}/, s)
      assert_match(/name='#{@cf.name}'/, s)
      assert_match(/type=#{@cf.ctype}/, s)
    end

    def test_inspect
      assert_equal @cf.inspect, @cf.to_s
    end

    def test_to_i
      assert_equal @cf.to_i, @cf.ptr
    end

    def test_last_error
      f = Function.new(@cf, [TYPE_VOIDP, TYPE_VOIDP])
      assert_nil CFunc.last_error
      str = f.call("000", "123")
      assert_not_nil CFunc.last_error
    end
  end
end
