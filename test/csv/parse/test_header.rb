# -*- coding: utf-8 -*-
# frozen_string_literal: false

require_relative "../helper"

class TestCSVHeaders < Test::Unit::TestCase
  extend DifferentOFS

  def setup
    super
    @data = <<-CSV
first,second,third
A,B,C
1,2,3
    CSV
  end

  def test_first_row
    [:first_row, true].each do |setting|  # two names for the same setting
      # activate headers
      csv = nil
      assert_nothing_raised(Exception) do
        csv = CSV.parse(@data, headers: setting)
      end

      # first data row - skipping headers
      row = csv[0]
      assert_not_nil(row)
      assert_instance_of(CSV::Row, row)
      assert_equal([%w{first A}, %w{second B}, %w{third C}], row.to_a)

      # second data row
      row = csv[1]
      assert_not_nil(row)
      assert_instance_of(CSV::Row, row)
      assert_equal([%w{first 1}, %w{second 2}, %w{third 3}], row.to_a)

      # empty
      assert_nil(csv[2])
    end
  end

  def test_array_of_headers
    # activate headers
    csv = nil
    assert_nothing_raised(Exception) do
      csv = CSV.parse(@data, headers: [:my, :new, :headers])
    end

    # first data row - skipping headers
    row = csv[0]
    assert_not_nil(row)
    assert_instance_of(CSV::Row, row)
    assert_equal( [[:my, "first"], [:new, "second"], [:headers, "third"]],
                  row.to_a )

    # second data row
    row = csv[1]
    assert_not_nil(row)
    assert_instance_of(CSV::Row, row)
    assert_equal([[:my, "A"], [:new, "B"], [:headers, "C"]], row.to_a)

    # third data row
    row = csv[2]
    assert_not_nil(row)
    assert_instance_of(CSV::Row, row)
    assert_equal([[:my, "1"], [:new, "2"], [:headers, "3"]], row.to_a)

    # empty
    assert_nil(csv[3])

    # with return and convert
    assert_nothing_raised(Exception) do
      csv = CSV.parse( @data, headers:           [:my, :new, :headers],
                              return_headers:    true,
                              header_converters: lambda { |h| h.to_s } )
    end
    row = csv[0]
    assert_not_nil(row)
    assert_instance_of(CSV::Row, row)
    assert_equal([["my", :my], ["new", :new], ["headers", :headers]], row.to_a)
    assert_predicate(row, :header_row?)
    assert_not_predicate(row, :field_row?)
  end

  def test_csv_header_string
    # activate headers
    csv = nil
    assert_nothing_raised(Exception) do
      csv = CSV.parse(@data, headers: "my,new,headers")
    end

    # first data row - skipping headers
    row = csv[0]
    assert_not_nil(row)
    assert_instance_of(CSV::Row, row)
    assert_equal([%w{my first}, %w{new second}, %w{headers third}], row.to_a)

    # second data row
    row = csv[1]
    assert_not_nil(row)
    assert_instance_of(CSV::Row, row)
    assert_equal([%w{my A}, %w{new B}, %w{headers C}], row.to_a)

    # third data row
    row = csv[2]
    assert_not_nil(row)
    assert_instance_of(CSV::Row, row)
    assert_equal([%w{my 1}, %w{new 2}, %w{headers 3}], row.to_a)

    # empty
    assert_nil(csv[3])

    # with return and convert
    assert_nothing_raised(Exception) do
      csv = CSV.parse( @data, headers:           "my,new,headers",
                              return_headers:    true,
                              header_converters: :symbol )
    end
    row = csv[0]
    assert_not_nil(row)
    assert_instance_of(CSV::Row, row)
    assert_equal([[:my, "my"], [:new, "new"], [:headers, "headers"]], row.to_a)
    assert_predicate(row, :header_row?)
    assert_not_predicate(row, :field_row?)
  end

  def test_csv_header_string_inherits_separators
    # parse with custom col_sep
    csv = nil
    assert_nothing_raised(Exception) do
      csv = CSV.parse( @data.tr(",", "|"), col_sep: "|",
                                           headers: "my|new|headers" )
    end

    # verify headers were recognized
    row = csv[0]
    assert_not_nil(row)
    assert_instance_of(CSV::Row, row)
    assert_equal([%w{my first}, %w{new second}, %w{headers third}], row.to_a)
  end

  def test_return_headers
    # activate headers and request they are returned
    csv = nil
    assert_nothing_raised(Exception) do
      csv = CSV.parse(@data, headers: true, return_headers: true)
    end

    # header row
    row = csv[0]
    assert_not_nil(row)
    assert_instance_of(CSV::Row, row)
    assert_equal( [%w{first first}, %w{second second}, %w{third third}],
                  row.to_a )
    assert_predicate(row, :header_row?)
    assert_not_predicate(row, :field_row?)

    # first data row - skipping headers
    row = csv[1]
    assert_not_nil(row)
    assert_instance_of(CSV::Row, row)
    assert_equal([%w{first A}, %w{second B}, %w{third C}], row.to_a)
    assert_not_predicate(row, :header_row?)
    assert_predicate(row, :field_row?)

    # second data row
    row = csv[2]
    assert_not_nil(row)
    assert_instance_of(CSV::Row, row)
    assert_equal([%w{first 1}, %w{second 2}, %w{third 3}], row.to_a)
    assert_not_predicate(row, :header_row?)
    assert_predicate(row, :field_row?)

    # empty
    assert_nil(csv[3])
  end

  def test_converters
    # create test data where headers and fields look alike
    data = <<-CSV
1,2,3
1,2,3
    CSV

    # normal converters do not affect headers
    csv = CSV.parse( data, headers:        true,
                           return_headers: true,
                           converters:     :numeric )
    assert_equal([%w{1 1}, %w{2 2}, %w{3 3}], csv[0].to_a)
    assert_equal([["1", 1], ["2", 2], ["3", 3]], csv[1].to_a)
    assert_nil(csv[2])

    # header converters do affect headers (only)
    assert_nothing_raised(Exception) do
      csv = CSV.parse( data, headers:           true,
                             return_headers:    true,
                             converters:        :numeric,
                             header_converters: :symbol )
    end
    assert_equal([[:"1", "1"], [:"2", "2"], [:"3", "3"]], csv[0].to_a)
    assert_equal([[:"1", 1], [:"2", 2], [:"3", 3]], csv[1].to_a)
    assert_nil(csv[2])
  end

  def test_builtin_downcase_converter
    csv = CSV.parse( "One,TWO Three", headers:           true,
                                      return_headers:    true,
                                      header_converters: :downcase )
    assert_equal(%w{one two\ three}, csv.headers)
  end

  def test_builtin_symbol_converter
    # Note that the trailing space is intentional
    csv = CSV.parse( "One,TWO Three ", headers:           true,
                                       return_headers:    true,
                                       header_converters: :symbol )
    assert_equal([:one, :two_three], csv.headers)
  end

  def test_builtin_symbol_converter_with_punctuation
    csv = CSV.parse( "One, Two & Three ($)", headers:           true,
                                             return_headers:    true,
                                             header_converters: :symbol )
    assert_equal([:one, :two_three], csv.headers)
  end

  def test_builtin_converters_with_blank_header
    csv = CSV.parse( "one,,three", headers:           true,
                                   return_headers:    true,
                                   header_converters: [:downcase, :symbol] )
    assert_equal([:one, nil, :three], csv.headers)
  end

  def test_custom_converter
    converter = lambda { |header| header.tr(" ", "_") }
    csv       = CSV.parse( "One,TWO Three",
                           headers:           true,
                           return_headers:    true,
                           header_converters: converter )
    assert_equal(%w{One TWO_Three}, csv.headers)
  end

  def test_table_support
    csv = nil
    assert_nothing_raised(Exception) do
      csv = CSV.parse(@data, headers: true)
    end

    assert_instance_of(CSV::Table, csv)
  end

  def test_skip_blanks
    @data = <<-CSV


A,B,C

1,2,3



    CSV

    expected = [%w[1 2 3]]
    CSV.parse(@data, headers: true, skip_blanks: true) do |row|
      assert_equal(expected.shift, row.fields)
    end

    expected = [%w[A B C], %w[1 2 3]]
    CSV.parse( @data,
               headers:        true,
               return_headers: true,
               skip_blanks:    true ) do |row|
      assert_equal(expected.shift, row.fields)
    end
  end

  def test_headers_reader
    # no headers
    assert_nil(CSV.new(@data).headers)

    # headers
    csv = CSV.new(@data, headers: true)
    assert_equal(true, csv.headers)                    # before headers are read
    csv.shift                                          # set headers
    assert_equal(%w[first second third], csv.headers)  # after headers are read
  end

  def test_blank_row
    @data += "\n#{@data}"  # add a blank row

    # ensure that everything returned is a Row object
    CSV.parse(@data, headers: true) do |row|
      assert_instance_of(CSV::Row, row)
    end
  end

  def test_nil_row_header
    @data = <<-CSV
A

1
    CSV

    csv = CSV.parse(@data, headers: true)

    # ensure nil row creates Row object with headers
    row = csv[0]
    assert_equal([["A"], [nil]],
                 [row.headers, row.fields])
  end

  def test_parse_empty
    assert_equal(CSV::Table.new([], {}),
                 CSV.parse("", headers: true))
  end

  def test_parse_empty_line
    assert_equal(CSV::Table.new([], {}),
                 CSV.parse("\n", headers: true))
  end

  def test_specified_empty
    assert_equal(CSV::Table.new([],
                                headers: ["header1"]),
                 CSV.parse("", headers: ["header1"]))
  end

  def test_specified_empty_line
    assert_equal(CSV::Table.new([CSV::Row.new(["header1"], [])],
                                headers: ["header1"]),
                 CSV.parse("\n", headers: ["header1"]))
  end
end
