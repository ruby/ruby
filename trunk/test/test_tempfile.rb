require 'test/unit'
require 'tempfile'

class TestTempfile < Test::Unit::TestCase
  module M
  end

  def test_extend
    o = Tempfile.new("foo")
    o.extend M
    assert(M === o, "[ruby-dev:32932]")
  end
end

