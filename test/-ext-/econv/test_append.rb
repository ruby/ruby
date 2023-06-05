# frozen_string_literal: false
require 'test/unit'
require "-test-/econv"

class Test_EConvAppend < Test::Unit::TestCase
  def test_econv_str_append_valid
    ec = Bug::EConv.new("utf-8", "cp932")
    dst = "\u3044".encode("cp932")
    ret = ec.append("\u3042"*30, dst)
    assert_same(dst, ret)
    assert_not_predicate(dst, :ascii_only?)
    assert_predicate(dst, :valid_encoding?)
  end

  def test_econv_str_append_broken
    ec = Bug::EConv.new("utf-8", "cp932")
    dst = ""
    ret = ec.append("\u3042"*30, dst)
    assert_same(dst, ret)
    assert_not_predicate(dst, :ascii_only?)
    assert_not_predicate(dst, :valid_encoding?)
  end
end
