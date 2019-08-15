# -*- coding: utf-8 -*-
# frozen_string_literal: false

require_relative "../helper"

class TestCSVParseColumnSeparator < Test::Unit::TestCase
  extend DifferentOFS

  def test_comma
    assert_equal([["a", "b", nil, "d"]],
                 CSV.parse("a,b,,d", col_sep: ","))
  end

  def test_space
    assert_equal([["a", "b", nil, "d"]],
                 CSV.parse("a b  d", col_sep: " "))
  end

  def test_tab
    assert_equal([["a", "b", nil, "d"]],
                 CSV.parse("a\tb\t\td", col_sep: "\t"))
  end

  def test_multiple_characters_include_sub_separator
    assert_equal([["a b", nil, "d"]],
                 CSV.parse("a b    d", col_sep: "  "))
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
                 CSV.parse(data, col_sep: "<=>"))
  end
end
