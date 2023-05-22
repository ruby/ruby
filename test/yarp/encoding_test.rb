# frozen_string_literal: true

require "test_helper"

class EncodingTest < Test::Unit::TestCase
  %w[
    ascii
    ascii-8bit
    big5
    binary
    euc-jp
    iso-8859-1
    iso-8859-2
    iso-8859-3
    iso-8859-4
    iso-8859-5
    iso-8859-6
    iso-8859-7
    iso-8859-8
    iso-8859-9
    iso-8859-10
    iso-8859-11
    iso-8859-13
    iso-8859-14
    iso-8859-15
    iso-8859-16
    shift_jis
    us-ascii
    utf-8
    windows-31j
    windows-1251
    windows-1252
    CP1251
    CP1252
  ].each do |encoding|
    test "encoding: #{encoding}"  do
      result = YARP.parse_dup("# encoding: #{encoding}\nident")
      actual = result.value.statements.body.first.message.value.encoding
      assert_equal Encoding.find(encoding), actual
    end
  end

  test "coding"  do
    result = YARP.parse_dup("# coding: utf-8\nident")
    actual = result.value.statements.body.first.message.value.encoding
    assert_equal Encoding.find("utf-8"), actual
  end

  test "-*- emacs style -*-"  do
    result = YARP.parse_dup("# -*- coding: utf-8 -*-\nident")
    actual = result.value.statements.body.first.message.value.encoding
    assert_equal Encoding.find("utf-8"), actual
  end

  test "utf-8 variations" do
    %w[
      utf-8-unix
      utf-8-dos
      utf-8-mac
      utf-8-*
    ].each do |encoding|
      result = YARP.parse_dup("# coding: #{encoding}\nident")
      actual = result.value.statements.body.first.message.value.encoding
      assert_equal Encoding.find("utf-8"), actual
    end
  end
end
