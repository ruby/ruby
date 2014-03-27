require 'test/unit'
require 'super_module'

class TestSuperModule < Test::Unit::TestCase
  module Foo
    include SuperModule
    validates 'foo', presence: true

    def self.foo
      'self.foo'
    end

    def foo
      'foo'
    end
  end

  module Bar
    include SuperModule
    include Foo
    validates 'bar', presence: true

    class << self
      def bar
        'self.bar'
      end
    end

    def bar
      'bar'
    end
  end

  class FakeActiveRecord
    class << self
      def validates(attribute, options)
        validations << [attribute, options]
      end
      def validations
        @validations ||= []
      end
    end
    include Bar
  end

  def test_internal_class_method_invocations_in_base_class
    assert FakeActiveRecord.validations.include?(['foo', {presence: true}])
    assert FakeActiveRecord.validations.include?(['bar', {presence: true}])
  end

  def test_invoke_instance_methods_on_base_class
    instance = FakeActiveRecord.new

    assert_equal 'foo', instance.foo
    assert_equal 'bar', instance.bar
  end

  def test_invoke_class_methods_on_base_class
    assert_equal 'self.foo', FakeActiveRecord.foo
    assert_equal 'self.bar', FakeActiveRecord.bar
  end

end
