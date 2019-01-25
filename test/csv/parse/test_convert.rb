# -*- coding: utf-8 -*-
# frozen_string_literal: false

require_relative "../helper"

class TestCSVParseConvert < Test::Unit::TestCase
  extend DifferentOFS

  def setup
    super
    @data   = "Numbers,:integer,1,:float,3.015"
    @parser = CSV.new(@data)

    @custom = lambda {|field| /\A:(\S.*?)\s*\Z/ =~ field ? $1.to_sym : field}

    @time = Time.utc(2018, 12, 30, 6, 41, 29)
    @windows_safe_time_data = @time.strftime("%a %b %d %H:%M:%S %Y")
  end

  def test_integer
    @parser.convert(:integer)
    assert_equal(["Numbers", ":integer", 1, ":float", "3.015"],
                 @parser.shift)
  end

  def test_float
    @parser.convert(:float)
    assert_equal(["Numbers", ":integer", 1.0, ":float", 3.015],
                 @parser.shift)
  end

  def test_float_integer
    @parser.convert(:float)
    @parser.convert(:integer)
    assert_equal(["Numbers", ":integer", 1.0, ":float", 3.015],
                 @parser.shift)
  end

  def test_integer_float
    @parser.convert(:integer)
    @parser.convert(:float)
    assert_equal(["Numbers", ":integer", 1, ":float", 3.015],
                 @parser.shift)
  end

  def test_numberic
    @parser.convert(:numeric)
    assert_equal(["Numbers", ":integer", 1, ":float", 3.015],
                 @parser.shift)
  end

  def test_all
    @data   << ",#{@windows_safe_time_data}"
    @parser =  CSV.new(@data)
    @parser.convert(:all)
    assert_equal(["Numbers", ":integer", 1, ":float", 3.015, @time.to_datetime],
                 @parser.shift)
  end

  def test_custom
    @parser.convert do |field|
      /\A:(\S.*?)\s*\Z/ =~ field ? $1.to_sym : field
    end
    assert_equal(["Numbers", :integer, "1", :float, "3.015"],
                 @parser.shift)
  end

  def test_builtin_custom
    @parser.convert(:numeric)
    @parser.convert(&@custom)
    assert_equal(["Numbers", :integer, 1, :float, 3.015],
                 @parser.shift)
  end

  def test_custom_field_info_line
    @parser.convert do |field, info|
      assert_equal(1, info.line)
      info.index == 4 ? Float(field).floor : field
    end
    assert_equal(["Numbers", ":integer", "1", ":float", 3],
                 @parser.shift)
  end

  def test_custom_field_info_header
    headers = ["one", "two", "three", "four", "five"]
    @parser = CSV.new(@data, headers: headers)
    @parser.convert do |field, info|
      info.header == "three" ? Integer(field) * 100 : field
    end
    assert_equal(CSV::Row.new(headers,
                              ["Numbers", ":integer", 100, ":float", "3.015"]),
                 @parser.shift)
  end

  def test_custom_blank_field
    converter = lambda {|field| field.nil?}
    row = CSV.parse_line('nil,', converters: converter)
    assert_equal([false, true], row)
  end

  def test_nil_value
    assert_equal(["nil", "", "a"],
                 CSV.parse_line(',"",a', nil_value: "nil"))
  end

  def test_empty_value
    assert_equal([nil, "empty", "a"],
                 CSV.parse_line(',"",a', empty_value: "empty"))
  end
end
