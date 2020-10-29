# frozen_string_literal: true
require 'test/unit'

class TestMicroJIT < Test::Unit::TestCase
  # MicroJIT's code invalidation mechanism can't invalidate
  # code that is executing. Test that we don't try to do that.
  def test_code_invalidation
    klass = Class.new do
      def alias_then_hash(klass, method_to_redefine)
        klass.alias_method(method_to_redefine, :itself)
        hash
      end
    end

    instance = klass.new
    i = 0
    while i < 12
      if i < 11
        instance.alias_then_hash(klass, :bar)
      else
        ret = instance.alias_then_hash(klass, :hash)
        assert(instance.equal?(ret))
      end
      i += 1
    end
  end
end
