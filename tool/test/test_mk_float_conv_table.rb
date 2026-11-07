# frozen_string_literal: true
require "test/unit"
require "envutil"

class TestMkFloatConvTable < Test::Unit::TestCase
  def test_table_is_up_to_date
    srcdir = File.expand_path("../..", __dir__)
    script = File.join(srcdir, "tool/mk_float_conv_table.rb")
    table = File.read(File.join(srcdir, "float_conv_table.h"))
    out, err, status = EnvUtil.invoke_ruby([script], "", true, true)
    assert_predicate(status, :success?, err)
    assert_equal(table, out)
  end
end
