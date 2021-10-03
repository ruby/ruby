# -*- coding: utf-8 -*-
# frozen_string_literal: false

require_relative "../helper"

class TestCSVParseInvalid < Test::Unit::TestCase
  def test_no_column_mixed_new_lines
    error = assert_raise(CSV::MalformedCSVError) do
      CSV.parse("\n" +
                "\r")
    end
    assert_equal("New line must be <\"\\n\"> not <\"\\r\"> in line 2.",
                 error.message)
  end

  def test_ignore_invalid_line
    csv = CSV.new(<<-CSV, headers: true, return_headers: true)
head1,head2,head3
aaa,bbb,ccc
ddd,ee"e.fff
ggg,hhh,iii
    CSV
    headers = ["head1", "head2", "head3"]
    assert_equal(CSV::Row.new(headers, headers),
                 csv.shift)
    assert_equal(CSV::Row.new(headers, ["aaa", "bbb", "ccc"]),
                 csv.shift)
    assert_equal(false, csv.eof?)
    error = assert_raise(CSV::MalformedCSVError) do
      csv.shift
    end
    assert_equal("Illegal quoting in line 3.",
                 error.message)
    assert_equal(false, csv.eof?)
    assert_equal(CSV::Row.new(headers, ["ggg", "hhh", "iii"]),
                 csv.shift)
    assert_equal(true, csv.eof?)
  end

  def test_ignore_invalid_line_cr_lf
    data = <<-CSV
"1","OK"\r
"2",""NOT" OK"\r
"3","OK"\r
CSV
    csv = CSV.new(data)

    assert_equal(['1', 'OK'], csv.shift)
    assert_raise(CSV::MalformedCSVError) { csv.shift }
    assert_equal(['3', 'OK'], csv.shift)
  end
end
