# frozen_string_literal: true

require "test/unit"
require "rbconfig"
require "find_executable"

class TestFindExecutable < Test::Unit::TestCase
  def test_find_executable_returns_command_and_arguments
    ruby = RbConfig.ruby
    command = File.basename(ruby, RbConfig::CONFIG["EXEEXT"])
    original_path = ENV["PATH"]
    ENV["PATH"] = File.dirname(ruby)

    found = EnvUtil.find_executable(command, "--version") do |output|
      output.start_with?("ruby ")
    end

    assert_equal([ruby, "--version"], found)
  ensure
    ENV["PATH"] = original_path
  end

  def test_find_executable_returns_nil_for_unknown_command
    assert_nil(EnvUtil.find_executable("test-unit-ruby-core-missing") { true })
  end
end
