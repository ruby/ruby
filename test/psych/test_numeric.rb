require 'psych/helper'

module Psych
  ###
  # Test numerics from YAML spec:
  # http://yaml.org/type/float.html
  # http://yaml.org/type/int.html
  class TestNumeric < TestCase
    def test_non_float_with_0
      str = Psych.load('--- 090')
      assert_equal '090', str
    end
  end
end
