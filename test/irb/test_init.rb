# frozen_string_literal: false
require "test/unit"
require "irb"

module TestIRB
  class TestInit < Test::Unit::TestCase
    def test_setup_with_argv_preserves_global_argv
      argv = ["foo", "bar"]
      with_argv(argv) do
        IRB.setup(eval("__FILE__"), argv: %w[-f])
        assert_equal argv, ARGV
      end
    end

    def test_setup_with_minimum_argv_does_not_change_dollar0
      orig = $0.dup
      IRB.setup(eval("__FILE__"), argv: %w[-f])
      assert_equal orig, $0
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
