# frozen_string_literal: true

require_relative "helper"

module MMTk
  class TestGC < TestCase
    def test_start_from_ractors_while_disabled
      assert_separately([], <<~RUBY)
        Warning[:experimental] = false

        GC.disable
        ractors = 4.times.map do
          Ractor.new do
            10.times { GC.start }
          end
        end
        ractors.each(&:join)

        assert_equal(true, GC.enable)
      RUBY
    end
  end
end
