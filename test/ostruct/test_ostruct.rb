require 'test/unit'
require 'ostruct'

class TC_OpenStruct < Test::Unit::TestCase
  def assert_not_respond_to(object, method, message="")
    _wrap_assertion do
      full_message = build_message(message, <<EOT, object, object.class, method)
<?>
of type <?>
expected not to respond_to\\?<?>.
EOT
      _wrap_assertion do
        if object.respond_to?(method)
          raise Test::Unit::AssertionFailedError, full_message, caller(5)
        end
      end
    end
  end

  def test_equality
    o1 = OpenStruct.new
    o2 = OpenStruct.new
    assert_equal(o1, o2)

    o1.a = 'a'
    assert_not_equal(o1, o2)

    o2.a = 'a'
    assert_equal(o1, o2)

    o1.a = 'b'
    assert_not_equal(o1, o2)

    o2 = Object.new
    o2.instance_eval{@table = {:a => 'b'}}
    assert_not_equal(o1, o2)
  end
  
  def test_inspect
    foo = OpenStruct.new
    assert_equal("#<OpenStruct>", foo.inspect)
    foo.bar = 1
    foo.baz = 2
    assert_equal("#<OpenStruct bar=1, baz=2>", foo.inspect)

    foo = OpenStruct.new
    foo.bar = OpenStruct.new
    assert_equal('#<OpenStruct bar=#<OpenStruct>>', foo.inspect)
    foo.bar.foo = foo
    assert_equal('#<OpenStruct bar=#<OpenStruct foo=#<OpenStruct ...>>>', foo.inspect)
  end

  def test_frozen
    o = OpenStruct.new
    o.a = 'a'
    o.freeze
    assert_raise(TypeError) {o.b = 'b'}
    assert_not_respond_to(o, :b)
  end
end
