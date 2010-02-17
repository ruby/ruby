require_relative 'test_base'
require 'dl/func'

module DL
  class TestMethod < TestBase
    def test_method_call
      f = Method.new(@libm['sinf'], [TYPE_FLOAT], TYPE_FLOAT)
      assert_in_delta 1.0, f.call(90 * Math::PI / 180), 0.0001
    end
  end
end
