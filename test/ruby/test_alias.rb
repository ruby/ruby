# frozen_string_literal: false
require 'test/unit'

class TestAlias < Test::Unit::TestCase
  class Alias0
    def foo
      "foo"
    end
  end

  class Alias1 < Alias0
    alias bar foo

    def foo
      "foo+#{super}"
    end
  end

  class Alias2 < Alias1
    alias baz foo
    undef foo
  end

  class Alias3 < Alias2
    def foo
      super
    end

    def bar
      super
    end

    def quux
      super
    end
  end

  class Alias4 < Alias0
    alias foo1 foo
    alias foo2 foo1
    alias foo3 foo2
  end

  class Alias5 < Alias4
    alias foo1 foo
    alias foo3 foo2
    alias foo2 foo1
  end

  def test_alias
    x = Alias2.new
    assert_equal "foo", x.bar
    assert_equal "foo+foo", x.baz
    assert_equal "foo+foo", x.baz   # test_check for cache

    x = Alias3.new
    assert_raise(NoMethodError) { x.foo }
    assert_equal "foo", x.bar
    assert_raise(NoMethodError) { x.quux }
  end

  def test_alias_inspect
    o = Alias4.new
    assert_equal("TestAlias::Alias4(TestAlias::Alias0)#foo()", o.method(:foo).inspect.split[1])
    assert_equal("TestAlias::Alias4(TestAlias::Alias0)#foo1(foo)()", o.method(:foo1).inspect.split[1])
    assert_equal("TestAlias::Alias4(TestAlias::Alias0)#foo2(foo)()", o.method(:foo2).inspect.split[1])
    assert_equal("TestAlias::Alias4(TestAlias::Alias0)#foo3(foo)()", o.method(:foo3).inspect.split[1])

    o = Alias5.new
    assert_equal("TestAlias::Alias5(TestAlias::Alias0)#foo()", o.method(:foo).inspect.split[1])
    assert_equal("TestAlias::Alias5(TestAlias::Alias0)#foo1(foo)()", o.method(:foo1).inspect.split[1])
    assert_equal("TestAlias::Alias5(TestAlias::Alias0)#foo2(foo)()", o.method(:foo2).inspect.split[1])
    assert_equal("TestAlias::Alias5(TestAlias::Alias0)#foo3(foo)()", o.method(:foo3).inspect.split[1])
  end

  def test_nonexistmethod
    assert_raise(NameError){
      Class.new{
        alias_method :foobarxyzzy, :barbaz
      }
    }
  end

  def test_send_alias
    x = "abc"
    class << x
      alias_method :try, :__send__
    end
    assert_equal("ABC", x.try(:upcase), '[ruby-dev:38824]')
  end

  def test_special_const_alias
    assert_raise(TypeError) do
      1.instance_eval do
        alias to_string to_s
      end
    end
  end

  def test_alias_with_zsuper_method
    c = Class.new
    c.class_eval do
      def foo
        :ok
      end
      def bar
        :ng
      end
      private :foo
    end
    d = Class.new(c)
    d.class_eval do
      public :foo
      alias bar foo
    end
    assert_equal(:ok, d.new.bar)
  end

  module SuperInAliasedModuleMethod
    module M
      def foo
        super << :M
      end

      alias bar foo
    end

    class Base
      def foo
        [:Base]
      end
    end

    class Derived < Base
      include M
    end
  end

  # [ruby-dev:46028]
  def test_super_in_aliased_module_method # fails in 1.8
    assert_equal([:Base, :M], SuperInAliasedModuleMethod::Derived.new.bar)
  end

  def test_alias_wb_miss
    assert_normal_exit "#{<<-"begin;"}\n#{<<-'end;'}"
    begin;
      require 'stringio'
      GC.verify_internal_consistency
      GC.start
      class StringIO
        alias_method :read_nonblock, :sysread
      end
      GC.verify_internal_consistency
    end;
  end

  def test_cyclic_zsuper
    bug9475 = '[ruby-core:60431] [Bug #9475]'

    a = Module.new do
      def foo
        "A"
      end
    end

    b = Class.new do
      include a
      attr_reader :b

      def foo
        @b ||= 0
        raise SystemStackError if (@b += 1) > 1
        # "foo from B"
        super + "B"
      end
    end

    c = Class.new(b) do
      alias orig_foo foo

      def foo
        # "foo from C"
        orig_foo + "C"
      end
    end

    b.class_eval do
      alias orig_foo foo
      attr_reader :b2

      def foo
        @b2 ||= 0
        raise SystemStackError if (@b2 += 1) > 1
        # "foo from B (again)"
        orig_foo + "B2"
      end
    end

    assert_nothing_raised(SystemStackError, bug9475) do
      assert_equal("ABC", c.new.foo, bug9475)
    end
  end

  def test_alias_in_module
    bug9663 = '[ruby-core:61635] [Bug #9663]'

    assert_separately(['-', bug9663], "#{<<-"begin;"}\n#{<<-'end;'}")
    begin;
      bug = ARGV[0]

      m = Module.new do
        alias orig_to_s to_s
      end

      o = Object.new.extend(m)
      assert_equal(o.to_s, o.orig_to_s, bug)
    end;
  end

  class C0; def foo; end; end
  class C1 < C0; alias bar foo; end

  def test_alias_method_equation
    obj = C1.new
    assert_equal(obj.method(:bar), obj.method(:foo))
    assert_equal(obj.method(:foo), obj.method(:bar))
  end

  def test_alias_class_method_added
    name = nil
    k = Class.new {
      def foo;end
      def self.method_added(mid)
        @name = instance_method(mid).original_name
      end
      alias bar foo
      name = @name
    }
    assert_equal(:foo, k.instance_method(:bar).original_name)
    assert_equal(:foo, name)
  end

  def test_alias_module_method_added
    name = nil
    k = Module.new {
      def foo;end
      def self.method_added(mid)
        @name = instance_method(mid).original_name
      end
      alias bar foo
      name = @name
    }
    assert_equal(:foo, k.instance_method(:bar).original_name)
    assert_equal(:foo, name)
  end

  def test_alias_suppressing_redefinition
    assert_in_out_err(%w[-w], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      class A
        def foo; end
        alias foo foo
        def foo; end
      end
    end;
  end

  class C2
    public :system
    alias_method :bar, :system
    alias_method :system, :bar
  end

  def test_zsuper_alias_visibility
    assert(C2.new.respond_to?(:system))
  end

  def test_alias_memory_leak
    assert_no_memory_leak([], "#{<<~"begin;"}", "#{<<~'end;'}", rss: true)
    begin;
      class A
        500.times do
          1000.times do |i|
            define_method(:"foo_#{i}") {}

            alias :"foo_#{i}" :"foo_#{i}"

            remove_method :"foo_#{i}"
          end
          GC.start
        end
      end
    end;
  end

  def test_alias_complemented_method
    assert_in_out_err(%w[-w], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      module M
        def foo = 1
        self.extend M
      end

      3.times{|i|
        module M
          alias foo2 foo
          remove_method :foo
          def foo = 2
        ensure
          remove_method :foo
          alias foo foo2
          remove_method :foo2
        end

        M.foo

        original_foo = M.method(:foo)

        M.class_eval do
          remove_method :foo
          def foo = 3
        end

        M.class_eval do
          remove_method :foo
          define_method :foo, original_foo
        end
      }
    end;
  end
end
