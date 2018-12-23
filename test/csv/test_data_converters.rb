#!/usr/bin/env ruby -w
# encoding: UTF-8
# frozen_string_literal: false

# tc_data_converters.rb
#
# Created by James Edward Gray II on 2005-10-31.

require_relative "base"

class TestCSV::DataConverters < TestCSV
  extend DifferentOFS

  def setup
    super
    @data   = "Numbers,:integer,1,:float,3.015"
    @parser = CSV.new(@data)

    @custom = lambda { |field| field =~ /\A:(\S.*?)\s*\Z/ ? $1.to_sym : field }

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

  def test_convert_with_builtin_integer
    # setup parser...
    assert_respond_to(@parser, :convert)
    assert_nothing_raised(Exception) { @parser.convert(:integer) }

    # and use
    assert_equal(["Numbers", ":integer", 1, ":float", "3.015"], @parser.shift)
  end

  def test_convert_with_builtin_float
    # setup parser...
    assert_respond_to(@parser, :convert)
    assert_nothing_raised(Exception) { @parser.convert(:float) }

    # and use
    assert_equal(["Numbers", ":integer", 1.0, ":float", 3.015], @parser.shift)
  end

  def test_convert_order_float_integer
    # floats first, then integers...
    assert_nothing_raised(Exception) do
      @parser.convert(:float)
      @parser.convert(:integer)
    end

    # gets us nothing but floats
    assert_equal( [String, String, Float, String, Float],
                  @parser.shift.map { |field| field.class } )
  end

  def test_convert_order_integer_float
    # integers have precendance...
    assert_nothing_raised(Exception) do
      @parser.convert(:integer)
      @parser.convert(:float)
    end

    # gives us proper number conversion
    assert_equal( [String, String, 0.class, String, Float],
                  @parser.shift.map { |field| field.class } )
  end

  def test_builtin_numeric_combo_converter
    # setup parser...
    assert_nothing_raised(Exception) { @parser.convert(:numeric) }

    # and use
    assert_equal( [String, String, 0.class, String, Float],
                  @parser.shift.map { |field| field.class } )
  end

  def test_builtin_all_nested_combo_converter
    # setup parser...
    @data   << ",#{@win_safe_time_str}"        # add a DateTime field
    @parser =  CSV.new(@data)                  # reset parser
    assert_nothing_raised(Exception) { @parser.convert(:all) }

    # and use
    assert_equal( [String, String, 0.class, String, Float, DateTime],
                  @parser.shift.map { |field| field.class } )
  end

  def test_convert_with_custom_code
    # define custom converter...
    assert_nothing_raised(Exception) do
      @parser.convert { |field| field =~ /\A:(\S.*?)\s*\Z/ ? $1.to_sym : field }
    end

    # and use
    assert_equal(["Numbers", :integer, "1", :float, "3.015"], @parser.shift)
  end

  def test_convert_with_custom_code_mix
    # mix built-in and custom...
    assert_nothing_raised(Exception) { @parser.convert(:numeric) }
    assert_nothing_raised(Exception) { @parser.convert(&@custom) }

    # and use
    assert_equal(["Numbers", :integer, 1, :float, 3.015], @parser.shift)
  end

  def test_convert_with_custom_code_using_field_info
    # define custom converter that uses field information...
    assert_nothing_raised(Exception) do
      @parser.convert do |field, info|
        assert_equal(1, info.line)
        info.index == 4 ? Float(field).floor : field
      end
    end

    # and use
    assert_equal(["Numbers", ":integer", "1", ":float", 3], @parser.shift)
  end

  def test_convert_with_custom_code_using_field_info_header
    @parser = CSV.new(@data, headers: %w{one two three four five})

    # define custom converter that uses field header information...
    assert_nothing_raised(Exception) do
      @parser.convert do |field, info|
        info.header == "three" ? Integer(field) * 100 : field
      end
    end

    # and use
    assert_equal( ["Numbers", ":integer", 100, ":float", "3.015"],
                  @parser.shift.fields )
  end

  def test_custom_converter_with_blank_field
    converter = lambda { |field| field.nil? }
    row = nil
    assert_nothing_raised(Exception) do
      row = CSV.parse_line('nil,', converters: converter)
    end
    assert_equal([false, true], row);
  end

  def test_shortcut_interface
    assert_equal( ["Numbers", ":integer", 1, ":float", 3.015],
                  CSV.parse_line(@data, converters: :numeric) )

    assert_equal( ["Numbers", ":integer", 1, ":float", 3.015],
                  CSV.parse_line(@data, converters: [:integer, :float]) )

    assert_equal( ["Numbers", :integer, 1, :float, 3.015],
                  CSV.parse_line(@data, converters: [:numeric, @custom]) )
  end

  def test_unconverted_fields_number
    row = CSV.parse_line(@data,
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

  def test_unconverted_fields_empty_line
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

  def test_unconverted_fields
    data = <<-CSV
first,second,third
1,2,3
    CSV
    row = nil
    assert_nothing_raised(Exception) do
      row = CSV.parse_line( data,
                            converters:         :numeric,
                            unconverted_fields: true,
                            headers:            :first_row )
    end
    assert_not_nil(row)
    assert_equal([["first", 1], ["second", 2], ["third", 3]], row.to_a)
    assert_respond_to(row, :unconverted_fields)
    assert_equal(%w{1 2 3}, row.unconverted_fields)

    assert_nothing_raised(Exception) do
      row = CSV.parse_line( data,
                            converters:         :numeric,
                            unconverted_fields: true,
                            headers:            :first_row,
                            return_headers:     true )
    end
    assert_not_nil(row)
    assert_equal( [%w{first first}, %w{second second}, %w{third third}],
                  row.to_a )
    assert_respond_to(row, :unconverted_fields)
    assert_equal(%w{first second third}, row.unconverted_fields)

    assert_nothing_raised(Exception) do
      row = CSV.parse_line( data,
                            converters:         :numeric,
                            unconverted_fields: true,
                            headers:            :first_row,
                            return_headers:     true,
                            header_converters:  :symbol )
    end
    assert_not_nil(row)
    assert_equal( [[:first, "first"], [:second, "second"], [:third, "third"]],
                  row.to_a )
    assert_respond_to(row, :unconverted_fields)
    assert_equal(%w{first second third}, row.unconverted_fields)

    assert_nothing_raised(Exception) do
      row = CSV.parse_line( data,
                            converters:         :numeric,
                            unconverted_fields: true,
                            headers:            %w{my new headers},
                            return_headers:     true,
                            header_converters:  :symbol )
    end
    assert_not_nil(row)
    assert_equal( [[:my, "my"], [:new, "new"], [:headers, "headers"]],
                  row.to_a )
    assert_respond_to(row, :unconverted_fields)
    assert_equal(Array.new, row.unconverted_fields)
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
