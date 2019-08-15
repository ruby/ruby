# coding: US-ASCII
# frozen_string_literal: false
require_relative 'helper'

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

  def test_level_assignment
    logger = Logger.new(nil)

    Logger::Severity.constants.each do |level|
      next if level == :UNKNOWN

      logger.send("#{level.downcase}!")
      assert(logger.level) == Logger::Severity.const_get(level)
    end
  end
end
