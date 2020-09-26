# frozen_string_literal: true
require 'test/unit'
require 'ostruct'
require 'yaml'

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
    assert_equal(false, foo.inspect.frozen?)

    foo = OpenStruct.new
    foo.bar = OpenStruct.new
    assert_equal('#<OpenStruct bar=#<OpenStruct>>', foo.inspect)
    foo.bar.foo = foo
    assert_equal('#<OpenStruct bar=#<OpenStruct foo=#<OpenStruct ...>>>', foo.inspect)
    assert_equal(false, foo.inspect.frozen?)
  end

  def test_frozen
    o = OpenStruct.new(foo: 42)
    o.a = 'a'
    o.freeze
    assert_raise(FrozenError) {o.b = 'b'}
    assert_not_respond_to(o, :b)
    assert_raise(FrozenError) {o.a = 'z'}
    assert_equal('a', o.a)
    assert_equal(42, o.foo)
    o = OpenStruct.new :a => 42
    def o.frozen?; nil end
    o.freeze
    assert_raise(FrozenError, '[ruby-core:22559]') {o.a = 1764}
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

  def test_to_h_with_block
    os = OpenStruct.new("country" => "Australia", :capital => "Canberra")
    assert_equal({"country" => "AUSTRALIA", "capital" => "CANBERRA" },
                 os.to_h {|name, value| [name.to_s, value.upcase]})
    assert_equal("Australia", os.country)
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
    assert_respond_to(os, :foo)
    assert_equal(42, os.foo)
    assert_equal([:foo, :foo=], os.singleton_methods.sort)
  end

  def test_does_not_redefine
    $VERBOSE, verbose_bak = nil, $VERBOSE
    os = OpenStruct.new(foo: 42)
    def os.foo
      43
    end
    os.foo = 44
    assert_equal(43, os.foo)
  ensure
    $VERBOSE = verbose_bak
  end

  def test_allocate_subclass
    bug = '[ruby-core:80292] [Bug #13358] allocate should not call initialize'
    c = Class.new(OpenStruct) {
      def initialize(x,y={})super(y);end
    }
    os = assert_nothing_raised(ArgumentError, bug) {c.allocate}
    assert_instance_of(c, os)
  end

  def test_initialize_subclass
    c = Class.new(OpenStruct) {
      def initialize(x,y={})super(y);end
    }
    o = c.new(1, {a: 42})
    assert_equal(42, o.dup.a)
    assert_equal(42, o.clone.a)
  end

  def test_private_method
    os = OpenStruct.new
    class << os
      private
      def foo
      end
    end
    assert_raise_with_message(NoMethodError, /private method/) do
      os.foo true, true
    end
  end

  def test_protected_method
    os = OpenStruct.new
    class << os
      protected
      def foo
      end
    end
    assert_raise_with_message(NoMethodError, /protected method/) do
      os.foo true, true
    end
  end

  def test_access_undefined
    os = OpenStruct.new
    assert_nil os.foo
  end

  def test_overridden_private_methods
    os = OpenStruct.new(puts: :foo, format: :bar)
    assert_equal(:foo, os.puts)
    assert_equal(:bar, os.format)
  end

  def test_overridden_public_methods
    os = OpenStruct.new(method: :foo, class: :bar)
    assert_equal(:foo, os.method)
    assert_equal(:bar, os.class)
  end

  def test_access_original_methods
    os = OpenStruct.new(method: :foo, hash: 42)
    assert_equal(os.object_id, os.method!(:object_id).call)
    assert_not_equal(42, os.hash!)
  end

  def test_override_subclass
    c = Class.new(OpenStruct) {
      def foo; :protect_me; end
      private def bar; :protect_me; end
      def inspect; 'protect me'; end
    }
    o = c.new(
      foo: 1, bar: 2, inspect: '3', # in subclass: protected
      table!: 4, # bang method: protected
      each_pair: 5, to_s: 'hello', # others: not protected
    )
    # protected:
    assert_equal(:protect_me, o.foo)
    assert_equal(:protect_me, o.send(:bar))
    assert_equal('protect me', o.inspect)
    assert_not_equal(4, o.send(:table!))
    # not protected:
    assert_equal(5, o.each_pair)
    assert_equal('hello', o.to_s)
  end

  def test_mistaken_subclass
    sub = Class.new(OpenStruct) do
      def [](k)
        __send__(k)
        super
      end

      def []=(k, v)
        @item_set = true
        __send__("#{k}=", v)
        super
      end
    end
    o = sub.new
    o.foo = 42
    assert_equal 42, o.foo
  end

  def test_ractor
    obj1 = OpenStruct.new(a: 42, b: 42)
    obj1.c = 42
    obj1.freeze

    obj2 = Ractor.new obj1 do |obj|
      obj
    end.take
    assert obj1.object_id == obj2.object_id
  end if defined?(Ractor)

  def test_legacy_yaml
    s = "--- !ruby/object:OpenStruct\ntable:\n  :foo: 42\n"
    o = YAML.load(s)
    assert_equal(42, o.foo)

    o = OpenStruct.new(table: {foo: 42})
    assert_equal({foo: 42}, YAML.load(YAML.dump(o)).table)
  end

  def test_yaml
    h = {name: "John Smith", age: 70, pension: 300.42}
    yaml = "--- !ruby/object:OpenStruct\nname: John Smith\nage: 70\npension: 300.42\n"
    os1 = OpenStruct.new(h)
    os2 = YAML.load(os1.to_yaml)
    assert_equal yaml, os1.to_yaml
    assert_equal os1, os2
    assert_equal true, os1.eql?(os2)
    assert_equal 300.42, os2.pension
  end

  def test_strict
    o = OpenStruct::Strict.new(foo: 42)
    assert_equal(42, o.foo)
    assert_raise(NoMethodError) { o.bar }
    o.bar = :ok
    assert_equal(:ok, o.bar)
  end
end
