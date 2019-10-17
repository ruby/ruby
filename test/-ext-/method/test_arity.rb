# frozen_string_literal: false
require '-test-/method'
require 'test/unit'

class Test_Method < Test::Unit::TestCase
  class TestArity < Test::Unit::TestCase
    class A
      def foo0()
      end
      def foom1(*a)
      end
      def foom2(a,*b)
      end
      def foo1(a)
      end
      def foo2(a,b)
      end
    end

    class B < A
      private :foo1, :foo2
    end

    METHODS = {foo0: 0, foo1: 1, foo2: 2, foom1: -1, foom2: -2}

    def test_base
      METHODS.each do |name, arity|
        assert_equal(arity, Bug::Method.mod_method_arity(A, name), "A##{name}")
      end
    end

    def test_zsuper
      METHODS.each do |name, arity|
        assert_equal(arity, Bug::Method.mod_method_arity(B, name), "B##{name}")
      end
    end
  end
end
