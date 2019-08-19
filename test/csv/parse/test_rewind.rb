# -*- coding: utf-8 -*-
# frozen_string_literal: false

require_relative "../helper"

class TestCSVParseRewind < Test::Unit::TestCase
  extend DifferentOFS

  def parse(data, options={})
    csv = CSV.new(data, options)
    records = csv.to_a
    csv.rewind
    [records, csv.to_a]
  end

  def test_default
    data = <<-CSV
Ruby,2.6.0,script
    CSV
    assert_equal([
                   [["Ruby", "2.6.0", "script"]],
                   [["Ruby", "2.6.0", "script"]],
                 ],
                 parse(data))
  end

  def test_have_headers
    data = <<-CSV
Language,Version,Type
Ruby,2.6.0,script
    CSV
    assert_equal([
                   [CSV::Row.new(["Language", "Version", "Type"],
                                 ["Ruby", "2.6.0", "script"])],
                   [CSV::Row.new(["Language", "Version", "Type"],
                                 ["Ruby", "2.6.0", "script"])],
                 ],
                 parse(data, headers: true))
  end
end
