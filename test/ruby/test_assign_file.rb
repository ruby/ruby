require 'test/unit'
require 'tempfile'
require "thread"
require_relative 'envutil'
require_relative 'ut_eof'

class TestAssignFile < Test::Unit::TestCase

  def test_raise
    __FILE__ = 'bob'
  end

end
