# coding: US-ASCII
# frozen_string_literal: false
require 'test/unit'
require 'logger'

class TestLoggerSeverity < Test::Unit::TestCase
  def test_enum
    logger_levels = Logger.constants
    levels = ["WARN", "UNKNOWN", "INFO", "FATAL", "DEBUG", "ERROR"]
    Logger::Severity.constants.each do |level|
      assert(levels.include?(level.to_s))
      assert(logger_levels.include?(level))
    end
    assert_equal(levels.size, Logger::Severity.constants.size)
  end
end
