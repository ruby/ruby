# frozen_string_literal: false
require 'test/unit'
require 'ostruct'

class TC_OpenStruct < Test::Unit::TestCase
  def test_initialize
    h = {name: "John Smith", age: 70, pension: 300}
    assert_equal h, OpenStruct.new(h).to_h
    assert_equal h, OpenStruct.new(OpenStruct.new(h)).to_h
    assert_equal h, OpenStruct.new(Struct.new(*h.keys).new(*h.values)).to_h
  end

  def test_respond_to
    o = OpenStruct.new
    o.a = 1
    assert_respond_to(o, :a)
    assert_respond_to(o, :a=)
  end

  def test_respond_to_with_lazy_getter
    o = OpenStruct.new a: 1
    assert_respond_to(o, :a)
    assert_respond_to(o, :a=)
  end

  def test_respond_to_allocated
    assert_not_respond_to(OpenStruct.allocate, :a)
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
    assert_raise(RuntimeError) {o.b = 'b'}
    assert_not_respond_to(o, :b)
    assert_raise(RuntimeError) {o.a = 'z'}
    assert_equal('a', o.a)
    o = OpenStruct.new :a => 42
    def o.frozen?; nil end
    o.freeze
    assert_raise(RuntimeError, '[ruby-core:22559]') {o.a = 1764}
  end

  def test_delete_field
    bug = '[ruby-core:33010]'
    o = OpenStruct.new
    assert_not_respond_to(o, :a)
    assert_not_respond_to(o, :a=)
    o.a = 'a'
    assert_respond_to(o, :a)
    assert_respond_to(o, :a=)
    a = o.delete_field :a
    assert_not_respond_to(o, :a, bug)
    assert_not_respond_to(o, :a=, bug)
    assert_equal(a, 'a')
    s = Object.new
    def s.to_sym
      :foo
    end
    o[s] = true
    assert_respond_to(o, :foo)
    assert_respond_to(o, :foo=)
    o.delete_field s
    assert_not_respond_to(o, :foo)
    assert_not_respond_to(o, :foo=)
  end

  def test_setter
    os = OpenStruct.new
    os[:foo] = :bar
    assert_equal :bar, os.foo
    os['foo'] = :baz
    assert_equal :baz, os.foo
  end

  def test_getter
    os = OpenStruct.new
    os.foo = :bar
    assert_equal :bar, os[:foo]
    assert_equal :bar, os['foo']
  end

  def test_dig
    os1 = OpenStruct.new
    os2 = OpenStruct.new
    os1.child = os2
    os2.foo = :bar
    os2.child = [42]
    assert_equal :bar, os1.dig("child", :foo)
    assert_nil os1.dig("parent", :foo)
    assert_raise(TypeError) { os1.dig("child", 0) }
  end

  def test_to_h
    h = {name: "John Smith", age: 70, pension: 300}
    os = OpenStruct.new(h)
    to_h = os.to_h
    assert_equal(h, to_h)

    to_h[:age] = 71
    assert_equal(70, os.age)
    assert_equal(70, h[:age])

    assert_equal(h, OpenStruct.new("name" => "John Smith", "age" => 70, pension: 300).to_h)
  end

  def test_each_pair
    h = {name: "John Smith", age: 70, pension: 300}
    os = OpenStruct.new(h)
    assert_same os, os.each_pair{ }
    assert_equal '#<Enumerator: #<OpenStruct name="John Smith", age=70, pension=300>:each_pair>', os.each_pair.inspect
    assert_equal [[:name, "John Smith"], [:age, 70], [:pension, 300]], os.each_pair.to_a
    assert_equal 3, os.each_pair.size
  end

  def test_eql_and_hash
    os1 = OpenStruct.new age: 70
    os2 = OpenStruct.new age: 70.0
    assert_equal os1, os2
    assert_equal false, os1.eql?(os2)
    assert_not_equal os1.hash, os2.hash
    assert_equal true, os1.eql?(os1.dup)
    assert_equal os1.hash, os1.dup.hash
  end

  def test_method_missing
    os = OpenStruct.new
    e = assert_raise(NoMethodError) { os.foo true }
    assert_equal :foo, e.name
    assert_equal [true], e.args
    assert_match(/#{__callee__}/, e.backtrace[0])
    e = assert_raise(ArgumentError) { os.send :foo=, true, true }
    assert_match(/#{__callee__}/, e.backtrace[0])
  end

  def test_accessor_defines_method
    os = OpenStruct.new(foo: 42)
    assert os.respond_to? :foo
    assert_equal([], os.singleton_methods)
    assert_equal(42, os.foo)
    assert_equal([:foo, :foo=], os.singleton_methods.sort)
  end

  def test_does_not_redefine
    os = OpenStruct.new(foo: 42)
    def os.foo
      43
    end
    os.foo = 44
    assert_equal(43, os.foo)
  end

  def test_allocate_subclass
    bug = '[ruby-core:80292] [Bug #13358] allocate should not call initialize'
    c = Class.new(OpenStruct) {
      def initialize(x,y={})super(y);end
    }
    os = assert_nothing_raised(ArgumentError, bug) {c.allocate}
    assert_instance_of(c, os)
  end
end
