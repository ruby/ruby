require_relative 'helper'
require "reline"

class Reline::Terminfo::Test < Reline::TestCase
  def setup
    Reline::Terminfo.setupterm(0, 2)
  end

  def test_tigetstr
    assert Reline::Terminfo.tigetstr('khome')
  rescue Reline::Terminfo::TerminfoError => e
    skip e.message
  end

  def test_tiparm
    assert Reline::Terminfo.tigetstr('khome').tiparm
  rescue Reline::Terminfo::TerminfoError => e
    skip e.message
  end

  def test_tigetstr_with_param
    assert Reline::Terminfo.tigetstr('cuu').include?('%p1%d')
  rescue Reline::Terminfo::TerminfoError => e
    skip e.message
  end

  def test_tiparm_with_param
    assert Reline::Terminfo.tigetstr('cuu').tiparm(4649).include?('4649')
  rescue Reline::Terminfo::TerminfoError => e
    skip e.message
  end
end if Reline::Terminfo.enabled?
