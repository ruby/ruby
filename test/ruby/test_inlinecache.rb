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
end
