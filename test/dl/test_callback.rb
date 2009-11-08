require_relative 'test_base'
require_relative '../ruby/envutil'

module DL
  class TestCallback < TestBase
    include DL

    def test_callback_with_string
      called_with = nil
      addr = set_callback(TYPE_VOID, 1) do |str|
        called_with = dlunwrap(str)
      end
      func = CFunc.new(addr, TYPE_VOID, 'test')

      func.call([dlwrap('foo')])
      assert_equal 'foo', called_with
    end

    def test_call_callback
      called = false

      addr = set_callback(TYPE_VOID, 0) do
        called = true
      end

      func = CFunc.new(addr, TYPE_VOID, 'test')
      func.call([])

      assert called, 'function should be called'
    end
  end
end
