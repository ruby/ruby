require 'test/unit'
require_relative 'envutil'

class TestDefined < Test::Unit::TestCase
  class Foo
    def foo
      p :foo
    end
    protected :foo
    def bar(f)
      yield(defined?(self.foo))
      yield(defined?(f.foo))
    end
    def baz(f)
    end
    attr_accessor :attr
    def attrasgn_test
      yield(defined?(self.attr = 1))
    end
  end

  def defined_test
    return !defined?(yield)
  end

  def test_defined
    $x = nil

    assert(defined?($x))		# global variable
    assert_equal('global-variable', defined?($x))# returns description

    assert_nil(defined?(foo))		# undefined
    foo=5
    assert(defined?(foo))		# local variable

    assert(defined?(Array))		# constant
    assert(defined?(::Array))		# toplevel constant
    assert(defined?(File::Constants))	# nested constant
    assert(defined?(Object.new))	# method
    assert(defined?(Object::new))	# method
    assert(!defined?(Object.print))	# private method
    assert(defined?(1 == 2))		# operator expression

    f = Foo.new
    assert_nil(defined?(f.foo))         # protected method
    f.bar(f) { |v| assert(v) }
    assert_nil(defined?(f.quux))        # undefined method
    assert_nil(defined?(f.baz(x)))      # undefined argument
    x = 0
    assert(defined?(f.baz(x)))
    assert_nil(defined?(f.quux(x)))
    assert(defined?(print(x)))
    assert_nil(defined?(quux(x)))
    assert(defined?(f.attr = 1))
    f.attrasgn_test { |v| assert(v) }

    assert(defined_test)		# not iterator
    assert(!defined_test{})	        # called as iterator

    /a/ =~ ''
    assert_equal nil, defined?($&)
    assert_equal nil, defined?($`)
    assert_equal nil, defined?($')
    assert_equal nil, defined?($+)
    assert_equal nil, defined?($1)
    assert_equal nil, defined?($2)
    /a/ =~ 'a'
    assert_equal 'global-variable', defined?($&)
    assert_equal 'global-variable', defined?($`)
    assert_equal 'global-variable', defined?($') # '
    assert_equal nil, defined?($+)
    assert_equal nil, defined?($1)
    assert_equal nil, defined?($2)
    /(a)/ =~ 'a'
    assert_equal 'global-variable', defined?($&)
    assert_equal 'global-variable', defined?($`)
    assert_equal 'global-variable', defined?($') # '
    assert_equal 'global-variable', defined?($+)
    assert_equal 'global-variable', defined?($1)
    assert_equal nil, defined?($2)
    /(a)b/ =~ 'ab'
    assert_equal 'global-variable', defined?($&)
    assert_equal 'global-variable', defined?($`)
    assert_equal 'global-variable', defined?($') # '
    assert_equal 'global-variable', defined?($+)
    assert_equal 'global-variable', defined?($1)
    assert_equal nil, defined?($2)

    assert_equal("nil", defined?(nil))
    assert_equal("true", defined?(true))
    assert_equal("false", defined?(false))
    assert_equal("expression", defined?(1))
  end

  def test_defined_impl_specific
    feature7035 = '[ruby-core:47558]' # not spec
    assert_predicate(defined?(Foo), :frozen?, feature7035)
    assert_same(defined?(Foo), defined?(Array), feature7035)
  end

  class TestAutoloadedSuperclass
    autoload :A, "a"
  end

  class TestAutoloadedSubclass < TestAutoloadedSuperclass
    def a?
      defined?(A)
    end
  end

  def test_autoloaded_subclass
    bug = "[ruby-core:35509]"

    x = TestAutoloadedSuperclass.new
    class << x
      def a?; defined?(A); end
    end
    assert_equal("constant", x.a?, bug)

    assert_equal("constant", TestAutoloadedSubclass.new.a?, bug)
  end

  class TestAutoloadedNoload
    autoload :A, "a"
    def a?
      defined?(A)
    end
    def b?
      defined?(A::B)
    end
  end

  def test_autoloaded_noload
    loaded = $".dup
    $".clear
    loadpath = $:.dup
    $:.clear
    x = TestAutoloadedNoload.new
    assert_equal("constant", x.a?)
    assert_nil(x.b?)
    assert_equal([], $")
  ensure
    $".replace(loaded)
    $:.replace(loadpath)
  end

  def test_exception
    bug5786 = '[ruby-dev:45021]'
    assert_nil(defined?(raise("[Bug#5786]")::A), bug5786)
  end

  def test_define_method
    bug6644 = '[ruby-core:45831]'
    a = Class.new do
      def self.def_f!;
        singleton_class.send(:define_method, :f) { defined? super }
      end
    end
    aa = Class.new(a)
    a.def_f!
    assert_nil(a.f)
    assert_nil(aa.f)
    aa.def_f!
    assert_equal("super", aa.f, bug6644)
    assert_nil(a.f, bug6644)
  end

  def test_super_in_included_method
    c0 = Class.new do
      def m
      end
    end
    m1 = Module.new do
      def m
        defined?(super)
      end
    end
    c = Class.new(c0) do include m1
      def m
        super
      end
    end
    assert_equal("super", c.new.m)
  end

  def test_super_in_block
    bug8367 = '[ruby-core:54769] [Bug #8367]'
    c = Class.new do
      def x; end
    end

    m = Module.new do
      def b; yield; end
      def x; b {return defined?(super)}; end
    end

    o = c.new
    o.extend(m)
    assert_equal("super", o.x)
  end

  def test_super_toplevel
    assert_separately([], "assert_nil(defined?(super))")
  end
end
