# -*- coding: us-ascii -*-
# frozen_string_literal: false
require 'test/unit'

class TestErbCommand < Test::Unit::TestCase
  def test_var
    assert_in_out_err(["-I#{File.expand_path('../../lib', __dir__)}", "-w",
                       File.expand_path("../../libexec/erb", __dir__),
                       "var=hoge"],
                      "<%=var%>", ["hoge"])
  end

  def test_template_file_encoding
    assert_in_out_err(["-I#{File.expand_path('../../lib', __dir__)}", "-w",
                       File.expand_path("../../libexec/erb", __dir__)],
                      "<%=''.encoding.to_s%>", ["UTF-8"])
  end
end
