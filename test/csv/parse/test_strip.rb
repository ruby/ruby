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

  def test_middle
    assert_equal(["a b"],
                 CSV.parse_line(%Q{a b}, strip: true))
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

  def test_do_not_strip_cr
    assert_equal([
                   ["a", "b "],
                   ["a", "b "],
                 ],
                 CSV.parse(%Q{"a" ,"b " \r} +
                           %Q{"a" ,"b " \r},
                           strip: true))
  end

  def test_do_not_strip_lf
    assert_equal([
                   ["a", "b "],
                   ["a", "b "],
                 ],
                 CSV.parse(%Q{"a" ,"b " \n} +
                           %Q{"a" ,"b " \n},
                           strip: true))
  end

  def test_do_not_strip_crlf
    assert_equal([
                   ["a", "b "],
                   ["a", "b "],
                 ],
                 CSV.parse(%Q{"a" ,"b " \r\n} +
                           %Q{"a" ,"b " \r\n},
                           strip: true))
  end
end
