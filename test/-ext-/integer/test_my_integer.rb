# frozen_string_literal: false
require 'test/unit'
require "-test-/integer"

class Test_MyInteger < Test::Unit::TestCase
  def test_my_integer_to_f
    assert_raise(NotImplementedError) do
      Bug::Integer::MyInteger.new.to_f
    end

    begin
      Bug::Integer::MyInteger.class_eval do
        def to_f
        end
      end

      assert_nothing_raised do
        Bug::Integer::MyInteger.new.to_f
      end
    ensure
      Bug::Integer::MyInteger.class_eval do
        remove_method :to_f
      end
    end
  end

  def test_my_integer_cmp
    assert_raise(NotImplementedError) do
      Bug::Integer::MyInteger.new <=> 0
    end

    begin
      Bug::Integer::MyInteger.class_eval do
        def <=>(other)
          0
        end
      end

      assert_nothing_raised do
        Bug::Integer::MyInteger.new <=> 0
      end
    ensure
      Bug::Integer::MyInteger.class_eval do
        remove_method :<=>
      end
    end
  end
end
