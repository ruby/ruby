# -*- coding: utf-8 -*-
# frozen_string_literal: false

require_relative "../helper"

class TestCSVParseQuoteCharNil < Test::Unit::TestCase
  extend DifferentOFS

  def test_full
    assert_equal(["a", "b"], CSV.parse_line(%Q{a,b}, quote_char: nil))
  end

  def test_end_with_nil
    assert_equal(["a", nil, nil, nil], CSV.parse_line(%Q{a,,,}, quote_char: nil))
  end

  def test_nil_nil
    assert_equal([nil, nil], CSV.parse_line(%Q{,}, quote_char: nil))
  end

  def test_unquoted_value_multiple_characters_col_sep
    data = %q{a<b<=>x}
    assert_equal([[%Q{a<b}, "x"]], CSV.parse(data, col_sep: "<=>", quote_char: nil))
  end

  def test_csv_header_string
    data = <<~DATA
      first,second,third
      A,B,C
      1,2,3
    DATA
    assert_equal(
      CSV::Table.new([
        CSV::Row.new(["my", "new", "headers"], ["first", "second", "third"]),
        CSV::Row.new(["my", "new", "headers"], ["A", "B", "C"]),
        CSV::Row.new(["my", "new", "headers"], ["1", "2", "3"])
      ]),
      CSV.parse(data, headers: "my,new,headers", quote_char: nil)
    )
  end

  def test_comma
    assert_equal([["a", "b", nil, "d"]],
                 CSV.parse("a,b,,d", col_sep: ",", quote_char: nil))
  end

  def test_space
    assert_equal([["a", "b", nil, "d"]],
                 CSV.parse("a b  d", col_sep: " ", quote_char: nil))
  end

  def encode_array(array, encoding)
    array.collect do |element|
      element ? element.encode(encoding) : element
    end
  end

  def test_space_no_ascii
    encoding = Encoding::UTF_16LE
    assert_equal([encode_array(["a", "b", nil, "d"], encoding)],
                 CSV.parse("a b  d".encode(encoding),
                           col_sep: " ".encode(encoding),
                           quote_char: nil))
  end

  def test_multiple_space
    assert_equal([["a b", nil, "d"]],
                 CSV.parse("a b    d", col_sep: "  ", quote_char: nil))
  end

  def test_multiple_characters_leading_empty_fields
    data = <<-CSV
<=><=>A<=>B<=>C
1<=>2<=>3
    CSV
    assert_equal([
                   [nil, nil, "A", "B", "C"],
                   ["1", "2", "3"],
                 ],
                 CSV.parse(data, col_sep: "<=>", quote_char: nil))
  end

  def test_line
    lines = [
      "abc,def\n",
    ]
    csv = CSV.new(lines.join(""), quote_char: nil)
    lines.each do |line|
      csv.shift
      assert_equal(line, csv.line)
    end
  end
end
