# -*- coding: us-ascii -*-
# frozen_string_literal: true

require 'test/unit'

class TestMethod < Test::Unit::TestCase
  def test_alias
    m0 = Module.new do
      def foo; :M0 end
    end
    m1 = Module.new do
      include m0
    end
    c = Class.new do
      include m1
      alias bar foo
    end
    d = Class.new(c) do
    end

    test = -> do
      d.new.bar
    end

    assert_equal :M0, test[]

    c.class_eval do
      def bar
        :C
      end
    end

    assert_equal :C, test[]
  end

  def test_zsuper
    assert_separately [], <<-EOS
      class C
        private def foo
          :C
        end
      end

      class D < C
        public :foo
      end

      class E < D; end
      class F < E; end

      test = -> do
        F.new().foo
      end

      assert_equal :C, test[]

      class E
        def foo; :E; end
      end

      assert_equal :E, test[]
    EOS
  end

  def test_module_methods_redefiniton
    m0 = Module.new do
      def foo
        super
      end
    end

    c1 = Class.new do
      def foo
        :C1
      end
    end

    c2 = Class.new do
      def foo
        :C2
      end
    end

    d1 = Class.new(c1) do
      include m0
    end

    d2 = Class.new(c2) do
      include m0
    end

    assert_equal :C1, d1.new.foo

    m = Module.new do
      def foo
        super
      end
    end

    d1.class_eval do
      include m
    end

    d2.class_eval do
      include m
    end

    assert_equal :C2, d2.new.foo
  end
end
