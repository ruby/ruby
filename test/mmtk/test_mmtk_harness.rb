# frozen_string_literal: true

require_relative "helper"

module MMTk
  class TestMMTkHarness < TestCase
    def test_harness_begin_end_output
      assert_in_out_err([], <<~RUBY) do |out, _err|
        GC::MMTk.harness_begin
        GC.start
        GC::MMTk.harness_end
      RUBY
        assert_match(/MMTk Statistics Totals/, out.join)
      end
    end
  end
end
