require_relative 'helper'
require "reline"

class Reline::Terminfo::Test < Reline::TestCase
  def setup
    Reline::Terminfo.setupterm(0, 2)
  rescue Reline::Terminfo::TerminfoError
    skip "Reline::Terminfo does not work"
  end

  def test_tigetstr
    assert Reline::Terminfo.tigetstr('khome')
  end

  def test_tiparm
    assert Reline::Terminfo.tigetstr('khome').tiparm
  end

  def test_tigetstr_with_param
    assert Reline::Terminfo.tigetstr('cuu').include?('%p1%d')
  end

  def test_tiparm_with_param
    assert Reline::Terminfo.tigetstr('cuu').tiparm(4649).include?('4649')
  end
end if Reline::Terminfo.enabled?
