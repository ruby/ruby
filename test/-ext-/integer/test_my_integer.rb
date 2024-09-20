# frozen_string_literal: false
require 'test/unit'
require "-test-/integer"

class Test_MyInteger < Test::Unit::TestCase
  def test_my_integer_to_f
    assert_raise(NotImplementedError) do
      Bug::Integer::MyInteger.new.to_f
    end

    int = Class.new(Bug::Integer::MyInteger) do
      def to_f
      end
    end

    assert_nothing_raised do
      int.new.to_f
    end
  end

  def test_my_integer_cmp
    assert_raise(NotImplementedError) do
      Bug::Integer::MyInteger.new <=> 0
    end

    int = Class.new(Bug::Integer::MyInteger) do
      def <=>(other)
        0
      end
    end

    assert_nothing_raised do
      int.new <=> 0
    end
  end
end
