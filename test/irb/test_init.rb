# frozen_string_literal: false
require "test/unit"
require "irb"

module TestIRB
  class TestInit < Test::Unit::TestCase
    def test_setup_with_argv_preserves_global_argv
      argv = ["foo", "bar"]
      with_argv(argv) do
        IRB.setup(eval("__FILE__"), argv: [])
        assert_equal argv, ARGV
      end
    end

    private

    def with_argv(argv)
      orig = ARGV.dup
      ARGV.replace(argv)
      yield
    ensure
      ARGV.replace(orig)
    end
  end
end
