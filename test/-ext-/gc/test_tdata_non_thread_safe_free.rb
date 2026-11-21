# frozen_string_literal: false
require 'test/unit'
require '-test-/gc/tdata_non_thread_safe_free'

class TestTDataNonThreadSafeFree < Test::Unit::TestCase
  def test_non_thread_safe_dfree_is_not_called_concurrently
    assert_ractor(<<~'RUBY', require: "-test-/gc/tdata_non_thread_safe_free")
      RACTORS = 4
      ITERS = 10
      BATCH = 10_000

      ractors = RACTORS.times.map do
        Ractor.new do
          ITERS.times { Bug::TDataNonThreadSafeFree.make(BATCH) }
          :done
        end
      end
      ractors.each(&:value)

      max = Bug::TDataNonThreadSafeFree.max_concurrent_free
      total = Bug::TDataNonThreadSafeFree.total_frees

      assert_operator total, :>, 0, "expected tdatas to have been freed (postponed job)"
      assert_operator max, :==, 1,
        "non-thread-safe dfree ran concurrently (BUG!): observed #{max} simultaneous " \
        "frees across #{total} total frees; Ractor-local GC must not invoke a dfree " \
        "for types lacking RUBY_TYPED_THREAD_SAFE_FREE"
    RUBY
  end

  def test_deferred_free_postponed_job
    # Create enough non-thread-safe T_DATA across multiple Ractors to exceed the
    # threshold, triggering the postponed job that sweeps them under the VM barrier
    # without a full global GC.
    assert_ractor(<<~'RUBY', require: "-test-/gc/tdata_non_thread_safe_free")
      Bug::TDataNonThreadSafeFree.reset

      RACTORS = 4
      BATCH = 10_000
      ITERS = 10

      ractors = RACTORS.times.map do
        Ractor.new do
          ITERS.times { Bug::TDataNonThreadSafeFree.make(BATCH) }
          :done
        end
      end
      ractors.each(&:value)
      assert_operator Bug::TDataNonThreadSafeFree.total_frees, :>, 0,
        "postponed job should have fired and freed deferred tdatas"

      max = Bug::TDataNonThreadSafeFree.max_concurrent_free
      assert_operator max, :==, 1,
        "non-thread-safe dfree ran concurrently (BUG!): observed #{max} simultaneous frees"
    RUBY
  end

  def test_single_ractor_freed_by_major_gc
    # Not assert_ractor: its preamble creates a Ractor to trigger the experimental
    # warning, which leaves single-Ractor mode for the rest of the process.
    assert_separately(["-r-test-/gc/tdata_non_thread_safe_free"], <<~'RUBY')
      Bug::TDataNonThreadSafeFree.reset

      BATCH = 50_000

      Bug::TDataNonThreadSafeFree.make(BATCH)
      GC.start

      total = Bug::TDataNonThreadSafeFree.total_frees
      assert_operator total, :>, 0,
        "expected a single-Ractor major GC to free non-thread-safe T_DATA"
    RUBY
  end

  def test_multi_ractor_under_threshold_no_postponed_job
    assert_ractor(<<~'RUBY', require: "-test-/gc/tdata_non_thread_safe_free")
      Bug::TDataNonThreadSafeFree.reset

      r = Ractor.new { receive }

      BATCH = 10_000
      before = GC.stat(:count)
      Bug::TDataNonThreadSafeFree.make(BATCH)
      after = GC.stat(:count)

      if before == after
        total = Bug::TDataNonThreadSafeFree.total_frees
        assert_operator total, :==, 0,
          "If didn't hit postponed job threshold or trigger GC, shouldn't have freed any"
      end
      r.send(nil); r.join
    RUBY
  end

  def test_multi_ractor_to_single_ractor_major_should_collect
    # Not assert_ractor: this test has to get back to single-Ractor mode, and the
    # preamble's unjoined Ractor keeps it out of it.
    assert_separately(["-r-test-/gc/tdata_non_thread_safe_free", "-W0"], <<~'RUBY')
      Bug::TDataNonThreadSafeFree.reset

      r = Ractor.new { receive }

      BATCH = 10_000
      before = GC.stat(:count)
      Bug::TDataNonThreadSafeFree.make(BATCH)
      after = GC.stat(:count)

      if before == after
        total = Bug::TDataNonThreadSafeFree.total_frees
        assert_operator total, :==, 0,
          "If didn't hit postponed job threshold or trigger global GC, shouldn't have freed any"
      end

      r.send(nil); r.value
      GC.start # single-ractor major GC
      total = Bug::TDataNonThreadSafeFree.total_frees
      assert_operator total, :>, 0,
        "expected a single-Ractor major GC to free non-thread-safe T_DATA"
    RUBY
  end

  def test_multi_ractor_global_gc_should_collect
    assert_ractor(<<~'RUBY', require: "-test-/gc/tdata_non_thread_safe_free")
      Bug::TDataNonThreadSafeFree.reset

      r = Ractor.new { receive }

      BATCH = 10_000
      before = GC.stat(:count)
      Bug::TDataNonThreadSafeFree.make(BATCH)
      after = GC.stat(:count)

      if before == after
        total = Bug::TDataNonThreadSafeFree.total_frees
        assert_operator total, :==, 0,
          "If didn't hit postponed job threshold or trigger GC, shouldn't have freed any"
      end

      GC.start # global GC
      total = Bug::TDataNonThreadSafeFree.total_frees
      assert_operator total, :>, 0,
        "expected a multi-ractor global GC to free non-thread-safe T_DATA (under barrier)"
      r.send(nil); r.join
    RUBY
  end

  def test_embeddable_non_thread_safe_free_is_not_embedded
    # A deferred free outlives its slot, so the payload must not live in the slot.
    # The control type differs only by RUBY_TYPED_THREAD_SAFE_FREE, proving that the
    # payload size is not what denied embedding.
    refute Bug::TDataNonThreadSafeFree.embeddable_embedded?,
      "an embeddable T_DATA without RUBY_TYPED_THREAD_SAFE_FREE must not be embedded"
    assert Bug::TDataNonThreadSafeFree.thread_safe_embeddable_embedded?,
      "an embeddable T_DATA with RUBY_TYPED_THREAD_SAFE_FREE should still be embedded"
  end

  def test_embeddable_freed_by_drain
    # An embeddable type that was not embedded: the GC xfrees the buffer after the
    # dfree, so the deferred entry has to remember that the type is embeddable.
    assert_separately(["-r-test-/gc/tdata_non_thread_safe_free", "-W0"], <<~'RUBY')
      Bug::TDataNonThreadSafeFree.reset

      r = Ractor.new { receive }

      BATCH = 30_000
      Bug::TDataNonThreadSafeFree.make_embeddable(BATCH)

      r.send(nil); r.value
      GC.start
      assert_operator Bug::TDataNonThreadSafeFree.embeddable_frees, :>, 0,
        "expected a single-Ractor major GC to drain the deferred frees"
    RUBY
  end

  def test_ruby_finalizer_and_dfree_both_run
    assert_ractor(<<~'RUBY', require: "-test-/gc/tdata_non_thread_safe_free")
      Bug::TDataNonThreadSafeFree.reset

      r = Ractor.new { receive }

      N = 100
      finalized = []
      # Built through a lambda so the finalizer's binding cannot reach the object.
      make_finalizer = ->(acc) { proc { acc << 1 } }
      N.times do
        obj = Bug::TDataNonThreadSafeFree.new
        ObjectSpace.define_finalizer(obj, make_finalizer.call(finalized))
      end

      GC.start
      r.send(nil); r.value
      GC.start

      assert_operator finalized.size, :>, 0,
        "a Ruby-level finalizer must still run on a deferred non-thread-safe T_DATA"
      assert_equal finalized.size, Bug::TDataNonThreadSafeFree.total_frees,
        "an object got its Ruby finalizer but not its deferred dfree, or vice versa"
    RUBY
  end

  def test_mixed_variants_never_free_concurrently
    assert_separately(["-r-test-/gc/tdata_non_thread_safe_free", "-W0"], <<~'RUBY')
      Bug::TDataNonThreadSafeFree.reset

      RACTORS = 4
      ITERS = 10

      assert_operator 4 * 10 * 2_000, :>, 2**15

      ractors = RACTORS.times.map do |n|
        Ractor.new(n) do |kind|
          ITERS.times do
            case kind % 2
            when 0 then Bug::TDataNonThreadSafeFree.make(2_000)
            else        Bug::TDataNonThreadSafeFree.make_embeddable(2_000)
            end
          end
          :done
        end
      end
      ractors.each(&:value)

      total = Bug::TDataNonThreadSafeFree.total_frees +
              Bug::TDataNonThreadSafeFree.embeddable_frees
      assert_operator total, :>, 0, "expected some tdatas to have been freed"

      max = Bug::TDataNonThreadSafeFree.max_concurrent_free
      assert_operator max, :==, 1,
        "non-thread-safe dfree ran concurrently (BUG!): observed #{max} simultaneous " \
        "frees across #{total} total"
    RUBY
  end

  # NullPayload wraps a NULL pointer. rb_data_free runs no dfree at all for a NULL payload,
  # so the deferred path must not run one either.
  def test_null_payload_is_not_deferred
    assert_ractor(<<~'RUBY', require: "-test-/gc/tdata_non_thread_safe_free")
      Bug::TDataNonThreadSafeFree.reset
      keep = Ractor.new { receive }

      Bug::TDataNonThreadSafeFree.make_null_payload(10_000)
      Bug::TDataNonThreadSafeFree.make_filled_payload(10_000)
      GC.start

      keep.send(nil); keep.value
      GC.start

      assert_equal 0, Bug::TDataNonThreadSafeFree.null_payload_null_frees,
        "dfree ran for a NULL payload"
      assert_operator Bug::TDataNonThreadSafeFree.null_payload_frees, :>, 0,
        "no dfree ran at all"
    RUBY
  end

  def test_null_payload_with_finalizer_still_runs_it
    assert_ractor(<<~'RUBY', require: "-test-/gc/tdata_non_thread_safe_free")
      Bug::TDataNonThreadSafeFree.reset
      keep = Ractor.new { receive }

      klass = Bug::TDataNonThreadSafeFree::NullPayload
      finalized = []
      make_finalizer = ->(acc) { proc { acc << 1 } }
      20_000.times do
        ObjectSpace.define_finalizer(klass.allocate, make_finalizer.call(finalized))
      end

      GC.start
      keep.send(nil); keep.value
      GC.start

      assert_operator finalized.size, :>, 0,
        "a Ruby finalizer on a NULL-payload deferred-free T_DATA was dropped"
      assert_equal 0, Bug::TDataNonThreadSafeFree.null_payload_null_frees,
        "dfree ran for a NULL payload"
    RUBY
  end

  # A dfree is allowed to free a dynamically allocated rb_data_type_t -- Bug::TypedData
  # .dynamic_type owns its type that way. The deferred entry must therefore resolve
  # everything it needs from the type before running the dfree; reading type->flags
  # afterwards is a use-after-free.
  def test_dfree_may_free_its_own_data_type
    assert_ractor(<<~'RUBY', require: "-test-/typeddata")
      keep = Ractor.new { receive }

      20_000.times { Bug::TypedData.dynamic_type }
      GC.start

      keep.send(nil); keep.value
      GC.start
      assert true
    RUBY
  end
end
