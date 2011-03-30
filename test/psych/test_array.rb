require 'psych/helper'

module Psych
  class TestArray < TestCase
    def setup
      super
      @list = [{ :a => 'b' }, 'foo']
    end

    def test_self_referential
      @list << @list
      assert_cycle(@list)
    end

    def test_cycle
      assert_cycle(@list)
    end
  end
end
