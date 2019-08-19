# -*- coding: us-ascii -*-
# frozen_string_literal: false
require 'test/unit'

class TestErbCommand < Test::Unit::TestCase
  def test_var
    assert_in_out_err(["-w",
                       File.expand_path("../../../bin/erb", __FILE__),
                       "var=hoge"],
                      "<%=var%>", ["hoge"])
  end

  def test_template_file_encoding
    assert_in_out_err(["-w",
                       File.expand_path("../../../bin/erb", __FILE__)],
                      "<%=''.encoding.to_s%>", ["UTF-8"])
  end

  # These interfaces will be removed at Ruby 2.7.
  def test_deprecated_option
    warnings = [
      "warning: -S option of erb command is deprecated. Please do not use this.",
      /\n.+\/bin\/erb:\d+: warning: Passing safe_level with the 2nd argument of ERB\.new is deprecated\. Do not use it, and specify other arguments as keyword arguments\.\n/,
    ]
    assert_in_out_err(["-w",
                       File.expand_path("../../../bin/erb", __FILE__),
                       "-S", "0"],
                      "hoge", ["hoge"], warnings)
  end
end
