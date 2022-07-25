# frozen_string_literal: true

require_relative "helper"
require "rubygems"

class TestExit < Gem::TestCase
  def test_exit
    system(*ruby_with_rubygems_in_load_path, "-e", "raise Gem::SystemExitException.new(2)")
    assert_equal 2, $?.exitstatus
  end

  def test_status
    exc = Gem::SystemExitException.new(42)
    assert_equal 42, exc.status
    assert_equal 42, exc.exit_code
  end
end
