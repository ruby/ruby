require 'psych/helper'

module Psych
  class TestClass < TestCase
    def test_cycle
      assert_raises(::TypeError) do
        assert_cycle(TestClass)
      end
    end

    def test_dump
      assert_raises(::TypeError) do
        Psych.dump TestClass
      end
    end
  end
end
