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

    def test_alias_with_time
      t    = Time.now
      h    = {:a => t, :b => t}
      yaml = Psych.dump h
      assert_match('&', yaml)
      assert_match('*', yaml)
    end
  end
end
