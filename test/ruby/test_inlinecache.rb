# -*- coding: us-ascii -*-
# frozen_string_literal: true

require 'test/unit'

class TestMethodInlineCache < Test::Unit::TestCase
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

  def test_undefined_method
    base = Class.new
    sub = Class.new(base)
    obj = sub.new
    test = -> { obj.foo rescue :undefined }

    2.times { assert_equal :undefined, test[] }
    base.class_eval { def foo = :base }
    assert_equal :base, test[]
    sub.class_eval { undef_method :foo }
    2.times { assert_equal :undefined, test[] }
    sub.class_eval { def foo = :sub }
    assert_equal :sub, test[]
  end

  def test_undefined_method_defined_by_include_and_singleton
    c = Class.new
    obj = c.new
    test = -> { obj.foo rescue :undefined }

    2.times { assert_equal :undefined, test[] }
    c.include(Module.new { def foo = :module })
    assert_equal :module, test[]

    obj2 = Class.new.new
    test2 = -> { obj2.foo rescue :undefined }
    2.times { assert_equal :undefined, test2[] }
    def obj2.foo = :singleton
    assert_equal :singleton, test2[]
  end

  def test_undefined_method_with_method_missing
    c = Class.new do
      def method_missing(name, *args) = [:missing, name, *args]
      def respond_to_missing?(*) = true
    end
    obj = c.new
    test = -> { obj.foo(1) }

    2.times { assert_equal [:missing, :foo, 1], test[] }
    c.class_eval { def foo(x) = [:defined, x] }
    assert_equal [:defined, 1], test[]
    c.class_eval { remove_method :foo }
    assert_equal [:missing, :foo, 1], test[]
  end

  def test_undefined_method_defined_by_prepend_and_extend
    c = Class.new
    obj = c.new
    test = -> { obj.foo rescue :undefined }

    2.times { assert_equal :undefined, test[] }
    c.prepend(Module.new { def foo = :prepended })
    assert_equal :prepended, test[]

    obj2 = Class.new.new
    test2 = -> { obj2.foo rescue :undefined }
    2.times { assert_equal :undefined, test2[] }
    obj2.extend(Module.new { def foo = :extended })
    assert_equal :extended, test2[]
  end

  def test_undefined_method_defined_in_module_included_later
    m1 = Module.new
    m2 = Module.new { def foo = :m2 }
    c = Class.new { include m1 }
    sub = Class.new(c)
    obj = sub.new
    test = -> { obj.foo rescue :undefined }

    2.times { assert_equal :undefined, test[] }
    m1.include(m2)
    assert_equal :m2, test[]

    m3 = Module.new
    obj2 = Class.new { include m3 }.new
    test2 = -> { obj2.bar rescue :undefined }
    2.times { assert_equal :undefined, test2[] }
    m3.class_eval { def bar = :m3 }
    assert_equal :m3, test2[]
  end

  def test_undefined_method_defined_by_refinement
    assert_separately([], <<~'RUBY')
      class C; end
      module R
        refine(C) { def bar = :bar }
      end
      using R
      def test = (C.new.foo rescue :undefined)
      2.times { assert_equal :undefined, test }
      module R
        refine(C) { def foo = :refined }
      end
      assert_equal :refined, test
    RUBY
  end

  def test_undefined_method_in_box
    assert_separately([{'RUBY_BOX' => '1'}], <<~'RUBY', ignore_stderr: true)
      test = -> { "x".negative_cache_test rescue :undefined }
      2.times { assert_equal :undefined, test[] }

      box = Ruby::Box.new
      assert_equal [:undefined, :undefined, :box], box.eval(<<~'CODE')
        test = -> { "x".negative_cache_test rescue :undefined }
        results = [test[], test[]]
        class String
          def negative_cache_test = :box
        end
        results << test[]
      CODE

      assert_equal :undefined, test[]
    RUBY
  end

  def test_undefined_method_with_ractor
    assert_separately([], <<~'RUBY', ignore_stderr: true)
      c = Class.new
      obj = Ractor.make_shareable(c.new)
      def call_foo(o) = 3.times.map { o.foo rescue :undefined }

      assert_equal [:undefined] * 3, Ractor.new(obj) { |o| call_foo(o) }.value
      assert_equal [:undefined] * 3, call_foo(obj)
      c.class_eval { def foo = :defined }
      assert_equal [:defined] * 3, Ractor.new(obj) { |o| call_foo(o) }.value
      assert_equal [:defined] * 3, call_foo(obj)
    RUBY
  end
end
