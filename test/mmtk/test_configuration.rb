# frozen_string_literal: true
require_relative "helper"
module MMTk
  class TestConfiguration < TestCase
    def test_invalid_MMTK_THREADS
      exit_code = assert_in_out_err(
        [{ "MMTK_THREADS" => "foobar" }, "--"],
        "",
        [],
        ["[FATAL] Invalid MMTK_THREADS foobar"]
      )

      assert_equal(1, exit_code.exitstatus)
    end
  end
end
