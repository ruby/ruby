# frozen_string_literal: true

require "test/unit"
require "memory_status"

class TestMemoryStatus < Test::Unit::TestCase
  def setup
    omit("memory status is unsupported") unless defined?(Memory::Status)
  end

  def test_status_reports_numeric_values
    status = Memory::Status.new

    assert(status.members.any? { |member| status[member].to_i > 0 })
    assert_match(/\A\{[^}]+:\d+(?:,[^}]+:\d+)*\}\z/, status.to_s)
  end

  def test_parse_round_trips_status
    status = Memory::Status.new

    assert_equal(status, Memory::Status.parse(status.to_s))
  end
end
