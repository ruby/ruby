require 'psych/helper'

module Psych
  class TestClass < TestCase
    def test_cycle_anonymous_class
      assert_raises(::TypeError) do
        assert_cycle(Class.new)
      end
    end

    def test_cycle
      assert_cycle(TestClass)
    end

    def test_dump
      Psych.dump TestClass
    end
  end
end
