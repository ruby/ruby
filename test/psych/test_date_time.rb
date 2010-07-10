require_relative 'helper'
require 'date'

module Psych
  class TestDateTime < TestCase
    def test_string_tag
      dt = DateTime.now
      yaml = Psych.dump dt
      assert_match(/DateTime/, yaml)
    end

    def test_round_trip
      dt = DateTime.now
      assert_cycle dt
    end

    def test_round_trip_with_offset
      dt = DateTime.now
      dt = dt.new_offset(Rational(3671, 60 * 60 * 24))
      assert_cycle dt
    end
  end
end
