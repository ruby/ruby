# frozen_string_literal: false
require_relative 'helper'
require 'date'

module Psych
  class TestDateTime < TestCase
    def test_negative_year
      time = Time.utc -1, 12, 16
      assert_cycle time
    end

    def test_new_datetime
      assert_cycle DateTime.new
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
