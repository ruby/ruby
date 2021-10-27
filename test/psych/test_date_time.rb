# frozen_string_literal: true
require_relative 'helper'
require 'date'

module Psych
  class TestDateTime < TestCase
    def test_negative_year
      time = Time.utc(-1, 12, 16)
      assert_cycle time
    end

    def test_usec
      time = Time.utc(2017, 4, 13, 12, 0, 0, 5)
      assert_cycle time
    end

    def test_non_utc
      time = Time.new(2017, 4, 13, 12, 0, 0.5, "+09:00")
      assert_cycle time
    end

    def test_timezone_offset
      times = [Time.new(2017, 4, 13, 12, 0, 0, "+09:00"),
               Time.new(2017, 4, 13, 12, 0, 0, "-05:00")]
      cycled = Psych::unsafe_load(Psych.dump times)
      assert_match(/12:00:00 \+0900/, cycled.first.to_s)
      assert_match(/12:00:00 -0500/,  cycled.last.to_s)
    end

    def test_new_datetime
      assert_cycle DateTime.new
    end

    def test_datetime_non_utc
      dt = DateTime.new(2017, 4, 13, 12, 0, 0.5, "+09:00")
      assert_cycle dt
    end

    def test_datetime_timezone_offset
      times = [DateTime.new(2017, 4, 13, 12, 0, 0, "+09:00"),
               DateTime.new(2017, 4, 13, 12, 0, 0, "-05:00")]
      cycled = Psych::unsafe_load(Psych.dump times)
      assert_match(/12:00:00\+09:00/, cycled.first.to_s)
      assert_match(/12:00:00-05:00/,  cycled.last.to_s)
    end

    def test_invalid_date
      assert_cycle "2013-10-31T10:40:07-000000000000033"
    end

    def test_string_tag
      dt = DateTime.now
      yaml = Psych.dump dt
      assert_match(/DateTime/, yaml)
    end

    def test_round_trip
      dt = DateTime.now
      assert_cycle dt
    end

    def test_alias_with_time
      t    = Time.now
      h    = {:a => t, :b => t}
      yaml = Psych.dump h
      assert_match('&', yaml)
      assert_match('*', yaml)
    end
  end
end
