#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: false

require 'test/unit'
require File.join(File.dirname(__FILE__), 'setup_variant')
require 'stringio'
require 'time'

class TestJSONStringMatching < Test::Unit::TestCase
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
    assert_equal [ t ],
      JSON.parse(t_json, :create_additions => true,
        :match_string => { /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{4}\z/ => TestTime })
    assert_equal [ t.strftime('%FT%T%z') ],
      JSON.parse(t_json, :create_additions => true,
        :match_string => { /\A\d{3}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{4}\z/ => TestTime })
    assert_equal [ t.strftime('%FT%T%z') ],
      JSON.parse(t_json,
        :match_string => { /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{4}\z/ => TestTime })
  end
end
