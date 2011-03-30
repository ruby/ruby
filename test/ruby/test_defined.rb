require 'test/unit'

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
  end

  def test_autoloaded_noload
    loaded = $".dup
    $".clear
    x = TestAutoloadedNoload.new
    assert_equal("constant", x.a?)
    assert_equal([], $")
  ensure
    $".replace(loaded)
  end
end
