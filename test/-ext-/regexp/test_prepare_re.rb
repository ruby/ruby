# frozen_string_literal: false
require 'test/unit'
require '-test-/regexp'

class Test_RegexpPrepareRe < Test::Unit::TestCase
  def test_caller_frees_other_encoding_buffer
    re = Regexp.new("a")
    str = "あa"
    assert_equal [0, false], Bug::Regexp.legacy_prepare_re(re, "a")
    3.times do
      assert_equal [3, true], Bug::Regexp.legacy_prepare_re(re, str)
      assert_equal [2, true], Bug::Regexp.legacy_prepare_re(re, str.encode("EUC-JP"))
    end
    GC.start
    assert_equal 1, re =~ str
  end
end
