# frozen_string_literal: true

require_relative "helper"

module MMTk
  class TestOOM < TestCase
    def test_oom
      assert_in_out_err([{ "MMTK_HEAP_MAX" => "64MiB" }], <<~RUBY, [], /failed to allocate memory/)
        10_000_000.times.map do
          Object.new
        end
      RUBY
    end
  end
end
