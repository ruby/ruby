# -*- coding: utf-8 -*-
# frozen_string_literal: false

require_relative "../helper"

class TestCSVParseRowSeparator < Test::Unit::TestCase
  extend DifferentOFS
  include Helper

  def test_multiple_characters
    with_chunk_size("1") do
      assert_equal([["a"], ["b"]],
                   CSV.parse("a\r\nb\r\n", row_sep: "\r\n"))
    end
  end
end
