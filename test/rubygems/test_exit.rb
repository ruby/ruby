# frozen_string_literal: true

require_relative "helper"
require "rubygems"

class TestGemExit < Gem::TestCase
  def test_exit
    system(*ruby_with_rubygems_in_load_path, "-e", "raise Gem::SystemExitException.new(2)")
    # Process.last_status instead of $?, which Ruby::Box leaves uninitialized
    assert_equal 2, Process.last_status.exitstatus
  end

  def test_status
    exc = Gem::SystemExitException.new(42)
    assert_equal 42, exc.status
    assert_equal 42, exc.exit_code
  end
end
