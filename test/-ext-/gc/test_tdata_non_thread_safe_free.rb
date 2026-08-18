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
        "non-thread-safe dfree ran concurrently: observed #{max} simultaneous " \
        "frees across #{total} total; Ractor-local GC must not invoke a dfree " \
        "lacking RUBY_TYPED_THREAD_SAFE_FREE in parallel"
    RUBY
  end
end
