# frozen_string_literal: true

require 'test/unit'

class TestThreadTraceMemoryAllocations < Test::Unit::TestCase
  def test_disabled_trace_memory_allocations
    Thread.trace_memory_allocations = false

    assert_predicate Thread.current.memory_allocations, :nil?
  end

  def test_enabled_trace_memory_allocations
    Thread.trace_memory_allocations = true

    assert_not_nil(Thread.current.memory_allocations)
  end

  def test_only_this_thread_allocations_are_counted
    changed = {
      total_allocated_objects: 1000,
      total_malloc_bytes: 1_000_000,
      total_mallocs: 100
    }

    Thread.trace_memory_allocations = true

    assert_less_than(changed) do
      Thread.new do
       assert_greater_than(changed) do
          # This will allocate: 5k objects, 5k mallocs, 5MB
          allocate(5000, 1000)
       end
      end.join

      # This will allocate: 50 objects, 50 mallocs, 500 bytes
      allocate(50, 10)
    end
  end

  private

  def allocate(slots, bytes)
    Array.new(slots).map do
      '0' * bytes
    end
  end

  def assert_greater_than(keys)
    before = Thread.current.memory_allocations
    yield
    after = Thread.current.memory_allocations

    keys.each do |key, by|
      assert_operator(by, :<=, after[key]-before[key], "expected the #{key} to change more than #{by}")
    end
  end

  def assert_less_than(keys)
    before = Thread.current.memory_allocations
    yield
    after = Thread.current.memory_allocations

    keys.each do |key, by|
      assert_operator(by, :>, after[key]-before[key], "expected the #{key} to change less than #{by}")
    end
  end
end
