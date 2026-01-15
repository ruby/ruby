# frozen_string_literal: true
require_relative 'test_helper'
require 'time'

class JSONStringMatchingTest < Test::Unit::TestCase
  include JSON

  class TestTime < ::Time
    def self.json_create(string)
      Time.parse(string)
    end

    def to_json(*)
      %{"#{strftime('%FT%T%z')}"}
    end

    def ==(other)
      to_i == other.to_i
    end
  end

  def test_match_date
    t = TestTime.new
    t_json = [ t ].to_json
    time_regexp = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{4}\z/
    assert_equal [ t ],
      parse(
        t_json,
        :create_additions => true,
        :match_string => { time_regexp => TestTime }
      )
    assert_equal [ t.strftime('%FT%T%z') ],
      parse(
        t_json,
        :match_string => { time_regexp => TestTime }
      )
  end
end
