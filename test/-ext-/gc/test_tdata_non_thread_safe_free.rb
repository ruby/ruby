# frozen_string_literal: false
require 'test/unit'

class TestTDataNonThreadSafeFree < Test::Unit::TestCase
  def test_non_thread_safe_dfree_is_not_called_concurrently
    assert_ractor(<<~'RUBY', require: "-test-/gc/tdata_non_thread_safe_free")
      RACTORS = 8
      ITERS = 20
      BATCH = 12500

      # TODO: use GC.start once a `global: false` option is available
      ractors = RACTORS.times.map do
        Ractor.new do
          ITERS.times { Bug::TDataNonThreadSafeFree.make(BATCH) }
          :done
        end
      end
      ractors.each(&:value)

      max = Bug::TDataNonThreadSafeFree.max_concurrent_free
      total = Bug::TDataNonThreadSafeFree.total_frees

      assert_operator total, :>, 0,
        "expected objects to actually be freed"
      assert_operator max, :<=, 1,
        "non-thread-safe dfree ran concurrently (BUG!): observed #{max} simultaneous " \
        "frees across #{total} total; Ractor-local GC must not invoke a dfree " \
        "lacking RUBY_TYPED_THREAD_SAFE_FREE in parallel"
    RUBY
  end

  def test_deferred_free_postponed_job
    # Create enough non-thread-safe T_DATA across multiple Ractors to exceed
    # TDATA_DEFERRED_FREE_THRESHOLD (1<<16 = 65536), triggering the postponed
    # job that sweeps them under the VM barrier without a full global GC.
    assert_ractor(<<~'RUBY', require: "-test-/gc/tdata_non_thread_safe_free")
      Bug::TDataNonThreadSafeFree.reset

      RACTORS = 4
      BATCH = 20000
      ITERS = 10

      ractors = RACTORS.times.map do
        Ractor.new do
          ITERS.times { Bug::TDataNonThreadSafeFree.make(BATCH) }
          :done
        end
      end
      ractors.each(&:value)
      assert_operator Bug::TDataNonThreadSafeFree.total_frees, :>, 0,
        "A postponed job should have fired and freed deferred tdatas"
      assert_operator Bug::TDataNonThreadSafeFree.total_frees, :>=, 1 << 16,
        "A postponed job should have fired and freed at least 1 batch of deferred tdatas"
      3.times { GC.start } # free any leftovers, if any

      max = Bug::TDataNonThreadSafeFree.max_concurrent_free
      total = Bug::TDataNonThreadSafeFree.total_frees

      assert_equal RACTORS * ITERS * BATCH, total,
        "expected all objects to be freed"
      assert_operator max, :<=, 1,
        "non-thread-safe dfree ran concurrently under the barrier (BUG!): " \
        "observed #{max} simultaneous frees"
    RUBY
  end
end
