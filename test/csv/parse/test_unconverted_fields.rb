# -*- coding: utf-8 -*-
# frozen_string_literal: false

require_relative "../helper"

class TestCSVParseUnconvertedFields < Test::Unit::TestCase
  extend DifferentOFS

  def setup
    super
    @custom = lambda {|field| /\A:(\S.*?)\s*\Z/ =~ field ? $1.to_sym : field}

    @headers = ["first", "second", "third"]
    @data = <<-CSV
first,second,third
1,2,3
    CSV
  end


  def test_custom
    row = CSV.parse_line("Numbers,:integer,1,:float,3.015",
                         converters:         [:numeric, @custom],
                         unconverted_fields: true)
    assert_equal([
                   ["Numbers", :integer, 1, :float, 3.015],
                   ["Numbers", ":integer", "1", ":float", "3.015"],
                 ],
                 [
                   row,
                   row.unconverted_fields,
                 ])
  end

  def test_no_fields
    row = CSV.parse_line("\n",
                         converters:         [:numeric, @custom],
                         unconverted_fields: true)
    assert_equal([
                   [],
                   [],
                 ],
                 [
                   row,
                   row.unconverted_fields,
                 ])
  end

  def test_parsed_header
    row = CSV.parse_line(@data,
                         converters:         :numeric,
                         unconverted_fields: true,
                         headers:            :first_row)
    assert_equal([
                   CSV::Row.new(@headers,
                                [1, 2, 3]),
                   ["1", "2", "3"],
                 ],
                 [
                   row,
                   row.unconverted_fields,
                 ])
  end

  def test_return_headers
    row = CSV.parse_line(@data,
                         converters:         :numeric,
                         unconverted_fields: true,
                         headers:            :first_row,
                         return_headers:     true)
    assert_equal([
                   CSV::Row.new(@headers,
                                @headers),
                   @headers,
                 ],
                 [
                   row,
                   row.unconverted_fields,
                 ])
  end

  def test_header_converters
    row = CSV.parse_line(@data,
                         converters:         :numeric,
                         unconverted_fields: true,
                         headers:            :first_row,
                         return_headers:     true,
                         header_converters:  :symbol)
    assert_equal([
                   CSV::Row.new(@headers.collect(&:to_sym),
                                @headers),
                   @headers,
                 ],
                 [
                   row,
                   row.unconverted_fields,
                 ])
  end

  def test_specified_headers
    row = CSV.parse_line("\n",
                         converters:         :numeric,
                         unconverted_fields: true,
                         headers:            %w{my new headers},
                         return_headers:     true,
                         header_converters:  :symbol)
    assert_equal([
                   CSV::Row.new([:my, :new, :headers],
                                ["my", "new", "headers"]),
                   [],
                 ],
                 [
                   row,
                   row.unconverted_fields,
                 ])
  end
end
