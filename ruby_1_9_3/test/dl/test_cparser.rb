require_relative 'test_base'

require 'dl/cparser'

module DL
  class TestCParser < TestBase
    include DL::CParser

    def test_uint_ctype
      assert_equal(-DL::TYPE_INT, parse_ctype('uint'))
    end
  end
end
