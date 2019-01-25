# -*- coding: utf-8 -*-
# frozen_string_literal: false

require_relative "../helper"

class TestCSVParseLiberalParsing < Test::Unit::TestCase
  extend DifferentOFS

  def test_middle_quote_start
    input = '"Johnson, Dwayne",Dwayne "The Rock" Johnson'
    error = assert_raise(CSV::MalformedCSVError) do
      CSV.parse_line(input)
    end
    assert_equal("Illegal quoting in line 1.",
                 error.message)
    assert_equal(["Johnson, Dwayne", 'Dwayne "The Rock" Johnson'],
                 CSV.parse_line(input, liberal_parsing: true))
  end

  def test_middle_quote_end
    input = '"quoted" field'
    error = assert_raise(CSV::MalformedCSVError) do
      CSV.parse_line(input)
    end
    assert_equal("Do not allow except col_sep_split_separator " +
                 "after quoted fields in line 1.",
                 error.message)
    assert_equal(['"quoted" field'],
                 CSV.parse_line(input, liberal_parsing: true))
  end

  def test_quote_after_column_separator
    error = assert_raise(CSV::MalformedCSVError) do
      CSV.parse_line('is,this "three," or four,fields', liberal_parsing: true)
    end
    assert_equal("Unclosed quoted field in line 1.",
                 error.message)
  end

  def test_quote_before_column_separator
    assert_equal(["is", 'this "three', ' or four"', "fields"],
                 CSV.parse_line('is,this "three, or four",fields',
                                liberal_parsing: true))
  end

  def test_backslash_quote
    assert_equal([
                   "1",
                   "\"Hamlet says, \\\"Seems",
                   "\\\" madam! Nay it is; I know not \\\"seems.\\\"\"",
                 ],
                 CSV.parse_line('1,' +
                                '"Hamlet says, \"Seems,' +
                                '\" madam! Nay it is; I know not \"seems.\""',
                                liberal_parsing: true))
  end

  def test_space_quote
    input = <<~CSV
      Los Angeles,   34°03'N,    118°15'W
      New York City, 40°42'46"N, 74°00'21"W
      Paris,         48°51'24"N, 2°21'03"E
    CSV
    assert_equal(
                 [
                   ["Los Angeles", "   34°03'N", "    118°15'W"],
                   ["New York City", " 40°42'46\"N", " 74°00'21\"W"],
                   ["Paris", "         48°51'24\"N", " 2°21'03\"E"],
                 ],
                 CSV.parse(input, liberal_parsing: true))
  end

  def test_double_quote_outside_quote
    data = %Q{a,""b""}
    error = assert_raise(CSV::MalformedCSVError) do
      CSV.parse(data)
    end
    assert_equal("Do not allow except col_sep_split_separator " +
                 "after quoted fields in line 1.",
                 error.message)
    assert_equal([
                   [["a", %Q{""b""}]],
                   [["a", %Q{"b"}]],
                 ],
                 [
                   CSV.parse(data, liberal_parsing: true),
                   CSV.parse(data,
                             liberal_parsing: {
                               double_quote_outside_quote: true,
                             }),
                 ])
  end
end
