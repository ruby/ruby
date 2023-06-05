# frozen_string_literal: false
require_relative 'test_optparse'

class TestOptionParserCClass < TestOptionParser
  def test_no_argument
    flags = []
    @opt.def_option("-[a-z]") {|x| flags << x}
    no_error {@opt.parse!(%w"-a")}
    assert_equal(%w"a", flags)
  end

  def test_required_argument
    flags = []
    @opt.def_option("-[a-z]X") {|x| flags << x}
    no_error {@opt.parse!(%w"-a")}
    assert_equal(%w"a", flags)
  end
end
