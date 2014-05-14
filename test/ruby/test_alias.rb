require 'test/unit'
require_relative 'envutil'

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

  class C
    def m
      $SAFE
    end
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
    assert_normal_exit %q{
      require 'stringio'
      GC.verify_internal_consistency
      GC.start
      class StringIO
        alias_method :read_nonblock, :sysread
      end
      GC.verify_internal_consistency
    }
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

    assert_separately(['-', bug9663], <<-'end;')
      bug = ARGV[0]

      m = Module.new do
        alias orig_to_s to_s
      end

      o = Object.new.extend(m)
      assert_equal(o.to_s, o.orig_to_s, bug)
    end;
  end
end
