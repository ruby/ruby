# frozen_string_literal: true
require_relative "helper"
module MMTk
  class TestConfiguration < TestCase
    def test_MMTK_THREADS
      assert_separately([{ "MMTK_THREADS" => "5" }], <<~RUBY)
        assert_equal(5, GC.config[:mmtk_worker_count])
      RUBY

      assert_separately([{ "MMTK_THREADS" => "1" }], <<~RUBY)
        assert_equal(1, GC.config[:mmtk_worker_count])
      RUBY
    end

    # TODO: Add NoGC once this is fixed: https://github.com/mmtk/mmtk-core/pull/1263
    %w(MarkSweep Immix).each do |plan|
      define_method(:"test_MMTK_PLAN_#{plan}") do
        assert_separately([{ "MMTK_PLAN" => plan }], <<~RUBY)
          assert_equal("#{plan}", GC.config[:mmtk_plan])
        RUBY
      end
    end

    %w(MMTK_THREADS MMTK_HEAP_MIN MMTK_HEAP_MAX MMTK_HEAP_MODE MMTK_PLAN).each do |var|
      define_method(:"test_invalid_#{var}") do
        exit_code = assert_in_out_err(
          [{ var => "foobar" }, "--"],
          "",
          [],
          ["[FATAL] Invalid #{var} foobar"]
        )

        assert_equal(1, exit_code.exitstatus)
      end
    end

    def test_MMTK_HEAP_MIN_greater_than_or_equal_to_MMTK_HEAP_MAX
      exit_code = assert_in_out_err(
        [{ "MMTK_HEAP_MIN" => "100MiB", "MMTK_HEAP_MAX" => "10MiB" }, "--"],
        "",
        [],
        ["[FATAL] MMTK_HEAP_MIN(104857600) >= MMTK_HEAP_MAX(10485760)"]
      )

      assert_equal(1, exit_code.exitstatus)

      exit_code = assert_in_out_err(
        [{ "MMTK_HEAP_MIN" => "10MiB", "MMTK_HEAP_MAX" => "10MiB" }, "--"],
        "",
        [],
        ["[FATAL] MMTK_HEAP_MIN(10485760) >= MMTK_HEAP_MAX(10485760)"]
      )

      assert_equal(1, exit_code.exitstatus)
    end
  end
end
