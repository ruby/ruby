# frozen_string_literal: true

require_relative "helper"

module MMTk
  class TestStat < TestCase
    def test_moving_gc_count
      assert_separately([{ "MMTK_PLAN" => "Immix" }], <<~RUBY)
        before = nil
        after = nil

        before = GC.stat(:moving_gc_count)

        2.times { GC.start }

        after = GC.stat(:moving_gc_count)

        assert_operator(before, :<, after)
      RUBY
    end

    def test_weak_references_count
      assert_operator(GC.stat(:weak_references_count), :>, 0)

      EnvUtil.without_gc do
        before = GC.stat(:weak_references_count)
        ObjectSpace::WeakMap.new
        assert_operator(GC.stat(:weak_references_count), :>, before)
      end
    end
  end
end
