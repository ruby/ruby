# frozen_string_literal: false
require 'test/unit'

class TestTDataNonThreadSafeFree < Test::Unit::TestCase
  def test_non_thread_safe_dfree_is_not_called_concurrently
    assert_ractor(<<~'RUBY', require: "-test-/gc/tdata_non_thread_safe_free")
      RACTORS = 8
      ITERS = 20
      BATCH = 10000

      ractors = RACTORS.times.map do
        Ractor.new do
          ITERS.times { Bug::TDataNonThreadSafeFree.make(BATCH) }
          :done
        end
      end
      ractors.each(&:value)

      max = Bug::TDataNonThreadSafeFree.max_concurrent_free
      total = Bug::TDataNonThreadSafeFree.total_frees

      assert_operator total, :>, 0, "expected all tdatas to have been freed (finalizers or postponed job)"
      assert_operator max, :==, 1,
        "non-thread-safe dfree ran concurrently (BUG!): observed #{max} simultaneous " \
        "frees across #{total} total; Ractor-local GC must not invoke a dfree " \
        "for types lacking RUBY_TYPED_THREAD_SAFE_FREE"
    RUBY
  end

  def test_deferred_free_postponed_job
    # Create enough non-thread-safe T_DATA across multiple Ractors to exceed the
    # threshold (65536), triggering the postponed job that sweeps them under the
    # VM barrier without a full global GC.
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
        "Finalizers should have ran or postponed job should have fired and freed deferred tdatas"

      max = Bug::TDataNonThreadSafeFree.max_concurrent_free
      assert_operator max, :==, 1,
        "non-thread-safe dfree ran concurrently under the barrier (BUG!): " \
        "observed #{max} simultaneous frees"
    RUBY
  end

  def test_single_ractor_freed_by_major_gc
    assert_ractor(<<~'RUBY',  require: "-test-/gc/tdata_non_thread_safe_free")
      Bug::TDataNonThreadSafeFree.reset

      ITERS = 10
      BATCH = 50_000

      ITERS.times { Bug::TDataNonThreadSafeFree.make(BATCH) }
      GC.start

      total = Bug::TDataNonThreadSafeFree.total_frees
      assert_operator total, :==, ITERS * BATCH,
        "expected a single-Ractor major GC to free non-thread-safe T_DATA"
    RUBY
  end

  def test_multi_ractor_under_threshold_no_postponed_job
    assert_ractor(<<~'RUBY', require: "-test-/gc/tdata_non_thread_safe_free")
      Bug::TDataNonThreadSafeFree.reset

      r = Ractor.new { receive }

      BATCH = 30_000
      before = GC.stat(:count)
      Bug::TDataNonThreadSafeFree.make(BATCH)
      after = GC.stat(:count)

      if before == after
        total = Bug::TDataNonThreadSafeFree.total_frees
        assert_operator total, :==, 0, "If didn't hit postponed job threshold or trigger GC, shouldn't have freed any"
      end
      r.send(nil); r.join
    RUBY
  end

  def test_multi_ractor_to_single_ractor_major_should_collect
    assert_ractor(<<~'RUBY', require: "-test-/gc/tdata_non_thread_safe_free")
      Bug::TDataNonThreadSafeFree.reset

      r = Ractor.new { receive }

      BATCH = 30_000
      before = GC.stat(:count)
      Bug::TDataNonThreadSafeFree.make(BATCH)
      after = GC.stat(:count)

      if before == after
        total = Bug::TDataNonThreadSafeFree.total_frees
        assert_operator total, :==, 0, "If didn't hit postponed job threshold or trigger GC, shouldn't have freed any"
      end

      r.send(nil); r.value
      GC.start # single-ractor major GC
      total = Bug::TDataNonThreadSafeFree.total_frees
      assert_operator total, :==, BATCH,
        "expected a single-Ractor major GC to free non-thread-safe T_DATA"
    RUBY
  end

  def test_multi_ractor_global_gc_should_collect
    assert_ractor(<<~'RUBY', require: "-test-/gc/tdata_non_thread_safe_free")
      Bug::TDataNonThreadSafeFree.reset

      r = Ractor.new { receive }

      BATCH = 30_000
      before = GC.stat(:count)
      Bug::TDataNonThreadSafeFree.make(BATCH)
      after = GC.stat(:count)

      if before == after
        total = Bug::TDataNonThreadSafeFree.total_frees
        assert_operator total, :==, 0, "If didn't hit postponed job threshold or trigger GC, shouldn't have freed any"
      end

      GC.start # global GC
      total = Bug::TDataNonThreadSafeFree.total_frees
      assert_operator total, :==, BATCH,
        "expected a multi-ractor global GC to free non-thread-safe T_DATA (under barrier)"
      r.send(nil); r.join
    RUBY
  end
end
