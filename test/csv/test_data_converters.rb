# -*- coding: utf-8 -*-
# frozen_string_literal: false

require_relative "helper"

class TestCSVDataConverters < Test::Unit::TestCase
  extend DifferentOFS

  def setup
    super
    @win_safe_time_str = Time.now.strftime("%a %b %d %H:%M:%S %Y")
  end

  def test_builtin_integer_converter
    # does convert
    [-5, 1, 10000000000].each do |n|
      assert_equal(n, CSV::Converters[:integer][n.to_s])
    end

    # does not convert
    (%w{junk 1.0} + [""]).each do |str|
      assert_equal(str, CSV::Converters[:integer][str])
    end
  end

  def test_builtin_float_converter
    # does convert
    [-5.1234, 0, 2.3e-11].each do |n|
      assert_equal(n, CSV::Converters[:float][n.to_s])
    end

    # does not convert
    (%w{junk 1..0 .015F} + [""]).each do |str|
      assert_equal(str, CSV::Converters[:float][str])
    end
  end

  def test_builtin_date_converter
    # does convert
    assert_instance_of(
      Date,
      CSV::Converters[:date][@win_safe_time_str.sub(/\d+:\d+:\d+ /, "")]
    )

    # does not convert
    assert_instance_of(String, CSV::Converters[:date]["junk"])
  end

  def test_builtin_date_time_converter
    # does convert
    assert_instance_of( DateTime,
                        CSV::Converters[:date_time][@win_safe_time_str] )

    # does not convert
    assert_instance_of(String, CSV::Converters[:date_time]["junk"])
  end

  def test_builtin_date_time_converter_iso8601_date
    iso8601_string = "2018-01-14"
    datetime = DateTime.new(2018, 1, 14)
    assert_equal(datetime,
                 CSV::Converters[:date_time][iso8601_string])
  end

  def test_builtin_date_time_converter_iso8601_minute
    iso8601_string = "2018-01-14T22:25"
    datetime = DateTime.new(2018, 1, 14, 22, 25)
    assert_equal(datetime,
                 CSV::Converters[:date_time][iso8601_string])
  end

  def test_builtin_date_time_converter_iso8601_second
    iso8601_string = "2018-01-14T22:25:19"
    datetime = DateTime.new(2018, 1, 14, 22, 25, 19)
    assert_equal(datetime,
                 CSV::Converters[:date_time][iso8601_string])
  end

  def test_builtin_date_time_converter_iso8601_under_second
    iso8601_string = "2018-01-14T22:25:19.1"
    datetime = DateTime.new(2018, 1, 14, 22, 25, 19.1)
    assert_equal(datetime,
                 CSV::Converters[:date_time][iso8601_string])
  end

  def test_builtin_date_time_converter_iso8601_under_second_offset
    iso8601_string = "2018-01-14T22:25:19.1+09:00"
    datetime = DateTime.new(2018, 1, 14, 22, 25, 19.1, "+9")
    assert_equal(datetime,
                 CSV::Converters[:date_time][iso8601_string])
  end

  def test_builtin_date_time_converter_iso8601_offset
    iso8601_string = "2018-01-14T22:25:19+09:00"
    datetime = DateTime.new(2018, 1, 14, 22, 25, 19, "+9")
    assert_equal(datetime,
                 CSV::Converters[:date_time][iso8601_string])
  end

  def test_builtin_date_time_converter_iso8601_utc
    iso8601_string = "2018-01-14T22:25:19Z"
    datetime = DateTime.new(2018, 1, 14, 22, 25, 19)
    assert_equal(datetime,
                 CSV::Converters[:date_time][iso8601_string])
  end

  def test_builtin_date_time_converter_rfc3339_minute
    rfc3339_string = "2018-01-14 22:25"
    datetime = DateTime.new(2018, 1, 14, 22, 25)
    assert_equal(datetime,
                 CSV::Converters[:date_time][rfc3339_string])
  end

  def test_builtin_date_time_converter_rfc3339_second
    rfc3339_string = "2018-01-14 22:25:19"
    datetime = DateTime.new(2018, 1, 14, 22, 25, 19)
    assert_equal(datetime,
                 CSV::Converters[:date_time][rfc3339_string])
  end

  def test_builtin_date_time_converter_rfc3339_under_second
    rfc3339_string = "2018-01-14 22:25:19.1"
    datetime = DateTime.new(2018, 1, 14, 22, 25, 19.1)
    assert_equal(datetime,
                 CSV::Converters[:date_time][rfc3339_string])
  end

  def test_builtin_date_time_converter_rfc3339_under_second_offset
    rfc3339_string = "2018-01-14 22:25:19.1+09:00"
    datetime = DateTime.new(2018, 1, 14, 22, 25, 19.1, "+9")
    assert_equal(datetime,
                 CSV::Converters[:date_time][rfc3339_string])
  end

  def test_builtin_date_time_converter_rfc3339_offset
    rfc3339_string = "2018-01-14 22:25:19+09:00"
    datetime = DateTime.new(2018, 1, 14, 22, 25, 19, "+9")
    assert_equal(datetime,
                 CSV::Converters[:date_time][rfc3339_string])
  end

  def test_builtin_date_time_converter_rfc3339_utc
    rfc3339_string = "2018-01-14 22:25:19Z"
    datetime = DateTime.new(2018, 1, 14, 22, 25, 19)
    assert_equal(datetime,
                 CSV::Converters[:date_time][rfc3339_string])
  end

  def test_builtin_date_time_converter_rfc3339_tab_minute
    rfc3339_string = "2018-01-14\t22:25"
    datetime = DateTime.new(2018, 1, 14, 22, 25)
    assert_equal(datetime,
                 CSV::Converters[:date_time][rfc3339_string])
  end

  def test_builtin_date_time_converter_rfc3339_tab_second
    rfc3339_string = "2018-01-14\t22:25:19"
    datetime = DateTime.new(2018, 1, 14, 22, 25, 19)
    assert_equal(datetime,
                 CSV::Converters[:date_time][rfc3339_string])
  end

  def test_builtin_date_time_converter_rfc3339_tab_under_second
    rfc3339_string = "2018-01-14\t22:25:19.1"
    datetime = DateTime.new(2018, 1, 14, 22, 25, 19.1)
    assert_equal(datetime,
                 CSV::Converters[:date_time][rfc3339_string])
  end

  def test_builtin_date_time_converter_rfc3339_tab_under_second_offset
    rfc3339_string = "2018-01-14\t22:25:19.1+09:00"
    datetime = DateTime.new(2018, 1, 14, 22, 25, 19.1, "+9")
    assert_equal(datetime,
                 CSV::Converters[:date_time][rfc3339_string])
  end

  def test_builtin_date_time_converter_rfc3339_tab_offset
    rfc3339_string = "2018-01-14\t22:25:19+09:00"
    datetime = DateTime.new(2018, 1, 14, 22, 25, 19, "+9")
    assert_equal(datetime,
                 CSV::Converters[:date_time][rfc3339_string])
  end

  def test_builtin_date_time_converter_rfc3339_tab_utc
    rfc3339_string = "2018-01-14\t22:25:19Z"
    datetime = DateTime.new(2018, 1, 14, 22, 25, 19)
    assert_equal(datetime,
                 CSV::Converters[:date_time][rfc3339_string])
  end
end
