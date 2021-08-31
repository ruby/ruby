require 'test/unit'

class TestNameError < Test::Unit::TestCase
  def test_new_default
    error = NameError.new
    assert_equal("NameError", error.message)
  end

  def test_new_message
    error = NameError.new("Message")
    assert_equal("Message", error.message)
  end

  def test_new_name
    error = NameError.new("Message")
    assert_nil(error.name)

    error = NameError.new("Message", :foo)
    assert_equal(:foo, error.name)
  end

  def test_new_receiver
    receiver = Object.new

    error = NameError.new
    assert_raise(ArgumentError) {error.receiver}
    assert_equal("NameError", error.message)

    error = NameError.new(receiver: receiver)
    assert_equal(["NameError", receiver],
                 [error.message, error.receiver])

    error = NameError.new("Message", :foo, receiver: receiver)
    assert_equal(["Message", receiver, :foo],
                 [error.message, error.receiver, error.name])
  end

  PrettyObject =
    Class.new(BasicObject) do
      alias object_id __id__
      def pretty_inspect; "`obj'"; end
      alias inspect pretty_inspect
    end

  def test_info_const
    obj = PrettyObject.new

    e = assert_raise(NameError) {
      obj.instance_eval("Object")
    }
    assert_equal(:Object, e.name)

    e = assert_raise(NameError) {
      BasicObject::X
    }
    assert_same(BasicObject, e.receiver)
    assert_equal(:X, e.name)
  end

  def test_info_const_name
    mod = Module.new do
      def self.name
        "ModuleName"
      end

      def self.inspect
        raise "<unusable info>"
      end
    end
    assert_raise_with_message(NameError, /ModuleName/) {mod::DOES_NOT_EXIST}
  end

  def test_info_method
    obj = PrettyObject.new

    e = assert_raise(NameError) {
      obj.instance_eval {foo}
    }
    assert_equal(:foo, e.name)
    assert_same(obj, e.receiver)

    e = assert_raise(NoMethodError) {
      obj.foo(1, 2)
    }
    assert_equal(:foo, e.name)
    assert_equal([1, 2], e.args)
    assert_same(obj, e.receiver)
    assert_not_predicate(e, :private_call?)

    e = assert_raise(NoMethodError) {
      obj.instance_eval {foo(1, 2)}
    }
    assert_equal(:foo, e.name)
    assert_equal([1, 2], e.args)
    assert_same(obj, e.receiver)
    assert_predicate(e, :private_call?)
  end

  def test_info_local_variables
    obj = PrettyObject.new
    def obj.test(a, b=nil, *c, &d)
      e = a
      1.times {|f| g = foo; g}
      e
    end

    e = assert_raise(NameError) {
      obj.test(3)
    }
    assert_equal(:foo, e.name)
    assert_same(obj, e.receiver)
    assert_equal(%i[a b c d e f g], e.local_variables.sort)
  end

  def test_info_method_missing
    obj = PrettyObject.new
    def obj.method_missing(*)
      super
    end

    e = assert_raise(NoMethodError) {
      obj.foo(1, 2)
    }
    assert_equal(:foo, e.name)
    assert_equal([1, 2], e.args)
    assert_same(obj, e.receiver)
    assert_not_predicate(e, :private_call?)

    e = assert_raise(NoMethodError) {
      obj.instance_eval {foo(1, 2)}
    }
    assert_equal(:foo, e.name)
    assert_equal([1, 2], e.args)
    assert_same(obj, e.receiver)
    assert_predicate(e, :private_call?)
  end

  def test_info_parent_iseq_mark
    assert_separately(['-', File.join(__dir__, 'bug-11928.rb')], <<-'end;')
      -> {require ARGV[0]}.call
    end;
  end

  def test_large_receiver_inspect
    receiver = Class.new do
      def self.inspect
        'A' * 120
      end
    end

    error = assert_raise(NameError) do
      receiver::FOO
    end
    assert_match(/\Auninitialized constant #{'A' * 120}::FOO$/, error.message)
  end
end
