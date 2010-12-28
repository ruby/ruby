require 'rubygems'
require 'minitest/autorun'
require 'rdoc/stats'
require 'rdoc/code_objects'
require 'rdoc/markup'
require 'rdoc/parser'

class TestRDocStats < MiniTest::Unit::TestCase

  def setup
    RDoc::TopLevel.reset

    @s = RDoc::Stats.new 0
  end

  def test_report_constant_alias
    tl = RDoc::TopLevel.new 'fake.rb'
    mod = tl.add_module RDoc::NormalModule, 'M'

    c = tl.add_class RDoc::NormalClass, 'C'
    mod.add_constant c

    ca = RDoc::Constant.new 'CA', nil, nil
    ca.is_alias_for = c

    tl.add_constant ca

    RDoc::TopLevel.complete :public

    report = @s.report

    # TODO change this to refute match, aliases should be ignored as they are
    # programmer convenience constructs
    assert_match(/class Object/, report)
  end

end

