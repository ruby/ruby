# frozen_string_literal: false
$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../../lib"

require 'test/unit'

class TestForTestHideSkip < Test::Unit::TestCase
  def test_omit
    omit "do nothing"
  end

  def test_pend
    pend "do nothing"
  end
end
