require 'test/unit'
require 'yaml'

class StructWithIvar < Struct.new(:foo)
  attr_reader :bar
  def initialize *args
    super
    @bar = 'hello'
  end
end

module Syck
  class TestStruct < MiniTest::Unit::TestCase
    def test_roundtrip
      thing = StructWithIvar.new('bar')
      struct = YAML.load(YAML.dump(thing))

      assert_equal 'hello', struct.bar
      assert_equal 'bar', struct.foo
    end

    def test_load
      obj = YAML.load(<<-eoyml)
--- !ruby/struct:StructWithIvar 
foo: bar
@bar: hello
      eoyml

      assert_equal 'hello', obj.bar
      assert_equal 'bar', obj.foo
    end
  end
end
