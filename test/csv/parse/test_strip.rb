# -*- coding: utf-8 -*-
# frozen_string_literal: false

require_relative "../helper"

class TestCSVParseStrip < Test::Unit::TestCase
  extend DifferentOFS

  def test_both
    assert_equal(["a", "b"],
                 CSV.parse_line(%Q{  a  ,  b  }, strip: true))
  end

  def test_left
    assert_equal(["a", "b"],
                 CSV.parse_line(%Q{  a,  b}, strip: true))
  end

  def test_right
    assert_equal(["a", "b"],
                 CSV.parse_line(%Q{a  ,b  }, strip: true))
  end

  def test_quoted
    assert_equal(["  a  ", "  b  "],
                 CSV.parse_line(%Q{"  a  ","  b  "}, strip: true))
  end

  def test_liberal_parsing
    assert_equal(["  a  ", "b", "  c  ", "  d  "],
                 CSV.parse_line(%Q{"  a  ",  b  ,  "  c  ","  d  "  },
                                strip: true,
                                liberal_parsing: true))
  end

  def test_string
    assert_equal(["a", " b"],
                 CSV.parse_line(%Q{  a  , " b"  },
                                strip: " "))
  end

  def test_no_quote
    assert_equal(["  a  ", "  b  "],
                 CSV.parse_line(%Q{"  a  ",  b  },
                                strip: %Q{"},
                                quote_char: nil))
  end
end
