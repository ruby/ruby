# frozen_string_literal: true
require_relative "helper"
module MMTk
  class TestConfiguration < TestCase
    %w(MMTK_THREADS MMTK_HEAP_MIN MMTK_HEAP_MAX).each do |var|
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
  end
end
