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
    assert(!defined?(Object.print))	# private method
    assert(defined?(1 == 2))		# operator expression

    f = Foo.new
    assert_nil(defined?(f.foo))
    f.bar(f) { |v| assert(v) }

    assert(defined_test)		# not iterator
    assert(!defined_test{})	# called as iterator
  end
end
