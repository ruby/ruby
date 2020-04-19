require_relative "test_helper"

class ObjectTest < StdlibTest
  target Object
  using hook.refinement

  def test_operators
    Object.new !~ 123

    Object.new <=> 123
    Object.new <=> Object.new

    Object.new === false
  end

  def test_class
    obj = Object.new

    obj.class
    obj.singleton_class
  end

  def test_clone
    Object.new.clone
    Object.new.clone(freeze: false)
  end

  def test_define_singleton_method
    Object.new.define_singleton_method(:foo) {|x, y, z| x+y+z }
    Object.new.define_singleton_method(:foo, Object.instance_method(:class))
  end

  def test_display
    Object.new.display()
    Object.new.display(STDOUT)
    Object.new.display(StringIO.new)
  end

  def test_dup
    Object.new.dup
  end

  def test_enum_for
    obj = Object.new

    obj.enum_for(:instance_exec)
    obj.enum_for(:instance_exec, 1,2,3)
    obj.enum_for(:instance_exec, 1,2,3) { |x,y,z| x + y + z }

    obj.to_enum(:instance_exec)
    obj.to_enum(:instance_exec, 1, 2, 3)
    obj.to_enum(:instance_exec, 1, 2, 3) { |x, y, z| x + y + z }
  end

  def test_eql
    Object.new.eql?(1)
  end

  def test_extend
    Object.new.extend(Math, Comparable, Enumerable)
  end

  def test_freeze
    Object.new.freeze
  end

  def test_frozen
    Object.new.frozen?
  end

  def test_hash
    Object.new.hash
  end

  def test_inspect
    Object.new.inspect
  end

  def test_instance_of?
    Object.new.instance_of?(Class)
  end

  def test_instance_variable_defined?
    Object.new.instance_variable_defined?(:@foo)
    Object.new.instance_variable_defined?("@foo")
  end

  def test_instance_variable_get
    Object.new.instance_variable_get(:@foo)
    Object.new.instance_variable_get("@bar")
  end

  def test_instance_variable_set
    Object.new.instance_variable_set(:@foo, 1)
    Object.new.instance_variable_set("@foo", 1)
  end

  def test_instance_variables
    Object.new.instance_variables
  end

  def test_is_a?
    Object.new.is_a?(Integer)
  end

  def test_itself
    Object.new.itself
  end

  def test_kind_of?
    Object.new.kind_of?(String)
  end

  def test_method
    obj = Object.new

    obj.method(:to_s)
    obj.public_method(:to_s)
  end

  def test_singleton_method
    obj = Object.new

    def obj.bar; end
    obj.singleton_method(:bar)
  end

  def test_methods
    obj = Object.new

    obj.methods
    obj.private_methods
    obj.public_methods
    obj.protected_methods
    obj.singleton_methods
  end

  def test_nil?
    Object.new.nil?
  end

  def test_object_id
    Object.new.object_id
  end

  def test_send
    obj = Object.new

    obj.send(:to_s)
    obj.send("is_a?", Object)
    obj.send("yield_self") {|x| x }

    obj.public_send(:to_s)
    obj.public_send("is_a?", Object)
    obj.public_send("yield_self") {|x| x }
  end

  def test_remove_instance_variable
    obj = Object.new

    obj.instance_variable_set("@foo", 1)
    obj.instance_variable_set("@bar", 2)

    obj.remove_instance_variable("@foo")
    obj.remove_instance_variable(:@bar)
  end

  def test_respond_to?
    obj = Object.new

    obj.respond_to?(:to_s)
    obj.respond_to?('to_s')
    obj.respond_to?('to_s', true)
  end

  def test_taint
    obj = Object.new

    obj.taint
    obj.tainted?
    obj.untaint
  end

  def test_tap
    obj = Object.new

    obj.tap do
    end
  end

  def test_yield_self
    obj = Object.new

    obj.yield_self { }
    obj.then { }
  end

  def test_to_s
    Object.new.to_s
  end
end
