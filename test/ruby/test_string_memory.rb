# frozen_string_literal: false
require 'test/unit'
require 'objspace'

class TestStringMemory < Test::Unit::TestCase
  def capture_allocations(klass)
    allocations = []

    GC.start
    GC.disable
    generation = GC.count

    ObjectSpace.trace_object_allocations do
      yield

      ObjectSpace.each_object(klass) do |instance|
        allocations << instance if ObjectSpace.allocation_generation(instance) == generation
      end
    end

    return allocations.map do |instance|
      [
        ObjectSpace.allocation_sourcefile(instance),
        ObjectSpace.allocation_sourceline(instance),
        instance.class,
        instance,
      ]
    end
  ensure
    GC.enable
  end

  def test_byteslice_prefix
    string = ("a" * 100_000).freeze

    allocations = capture_allocations(String) do
      string.byteslice(0, 50_000)
    end

    assert_equal 1, allocations.size, "One object allocation is expected, but allocated: #{ allocations.inspect }"
  end

  def test_byteslice_postfix
    string = ("a" * 100_000).freeze

    allocations = capture_allocations(String) do
      string.byteslice(50_000, 100_000)
    end

    assert_equal 1, allocations.size, "One object allocation is expected, but allocated: #{ allocations.inspect }"
  end

  def test_byteslice_postfix_twice
    string = ("a" * 100_000).freeze

    allocations = capture_allocations(String) do
      string.byteslice(50_000, 100_000).byteslice(25_000, 50_000)
    end

    assert_equal 2, allocations.size, "Two object allocations are expected, but allocated: #{ allocations.inspect }"
  end
end
