# -*- coding: utf-8 -*-
# frozen_string_literal: false

require_relative "../helper"

module TestCSVWriteQuoteEmpty
  def test_quote_empty_default
    assert_equal(%Q["""",""#{$INPUT_RECORD_SEPARATOR}],
                 generate_line([%Q["], ""]))
  end

  def test_quote_empty_false
    assert_equal(%Q["""",#{$INPUT_RECORD_SEPARATOR}],
                 generate_line([%Q["], ""],
                               quote_empty: false))
  end

  def test_empty_default
    assert_equal(%Q[foo,"",baz#{$INPUT_RECORD_SEPARATOR}],
                 generate_line(["foo", "", "baz"]))
  end

  def test_empty_false
    assert_equal(%Q[foo,,baz#{$INPUT_RECORD_SEPARATOR}],
                 generate_line(["foo", "", "baz"],
                               quote_empty: false))
  end

  def test_empty_only_default
    assert_equal(%Q[""#{$INPUT_RECORD_SEPARATOR}],
                 generate_line([""]))
  end

  def test_empty_only_false
    assert_equal(%Q[#{$INPUT_RECORD_SEPARATOR}],
                 generate_line([""],
                               quote_empty: false))
  end

  def test_empty_double_default
    assert_equal(%Q["",""#{$INPUT_RECORD_SEPARATOR}],
                 generate_line(["", ""]))
  end

  def test_empty_double_false
    assert_equal(%Q[,#{$INPUT_RECORD_SEPARATOR}],
                 generate_line(["", ""],
                               quote_empty: false))
  end
end

class TestCSVWriteQuoteEmptyGenerateLine < Test::Unit::TestCase
  include TestCSVWriteQuoteEmpty
  extend DifferentOFS

  def generate_line(row, **kwargs)
    CSV.generate_line(row, **kwargs)
  end
end

class TestCSVWriteQuoteEmptyGenerate < Test::Unit::TestCase
  include TestCSVWriteQuoteEmpty
  extend DifferentOFS

  def generate_line(row, **kwargs)
    CSV.generate(**kwargs) do |csv|
      csv << row
    end
  end
end
