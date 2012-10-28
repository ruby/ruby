require 'test/unit'
require 'ostruct'

class TC_OpenStruct < Test::Unit::TestCase
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

  def test_eql
    o1 = OpenStruct.new(:a=>'a')
    o2 = OpenStruct.new(:a=>'a')
    o3 = OpenStruct.new(:a=>'b')
    assert o1.eql?(o2)
    assert !o1.eql?(o3)
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
    assert_raise(TypeError) {o.a = 'z'}
    assert_equal('a', o.a)
    o = OpenStruct.new :a => 42
    def o.frozen?; nil end
    o.freeze
    assert_raise(TypeError, '[ruby-core:22559]') {o.a = 1764}
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
  end

  def test_square_bracket_equals
    o = OpenStruct.new
    o[:foo] = 40
    assert_equal(o[:foo], 40)
  end

  def test_square_brackets
    o = OpenStruct.new(:foo=>4)
    assert_equal(o[:foo], 4)
  end

  def test_merge
    o = OpenStruct.new(:foo=>4)
    o.merge!(:bar=>5)
    assert_equal(o.bar, 5)
    assert_equal(o.foo, 4)
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
end
