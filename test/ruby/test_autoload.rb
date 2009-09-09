require 'test/unit'
require_relative 'envutil'

class TestAutoload < Test::Unit::TestCase
  def test_autoload_so
    # Continuation is always available, unless excluded intentionally.
    assert_in_out_err([], <<-INPUT, [], [])
    autoload :Continuation, "continuation"
    begin Continuation; rescue LoadError; end
    INPUT
  end
end
