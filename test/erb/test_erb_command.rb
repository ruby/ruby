# -*- coding: us-ascii -*-
# frozen_string_literal: false
require 'test/unit'

class TestErbCommand < Test::Unit::TestCase
  def test_var
    pend if RUBY_ENGINE == 'truffleruby'
    assert_in_out_err(["-I#{File.expand_path('../../lib', __dir__)}",
                       File.expand_path("../../libexec/erb", __dir__),
                       "var=hoge"],
                      "<%=var%>", ["hoge"])
  end

  def test_template_file_encoding
    pend if RUBY_ENGINE == 'truffleruby'
    assert_in_out_err(["-I#{File.expand_path('../../lib', __dir__)}",
                       File.expand_path("../../libexec/erb", __dir__)],
                      "<%=''.encoding.to_s%>", ["UTF-8"])
  end
end
