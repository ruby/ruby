require 'test/unit'
require 'socket'

class TestSockOpt < Test::Unit::TestCase
  def test_bool
    opt = Socket::Option.bool(:INET, :SOCKET, :KEEPALIVE, true)
    assert_equal(1, opt.int)
    opt = Socket::Option.bool(:INET, :SOCKET, :KEEPALIVE, false)
    assert_equal(0, opt.int)
    opt = Socket::Option.int(:INET, :SOCKET, :KEEPALIVE, 0)
    assert_equal(false, opt.bool)
    opt = Socket::Option.int(:INET, :SOCKET, :KEEPALIVE, 1)
    assert_equal(true, opt.bool)
    opt = Socket::Option.int(:INET, :SOCKET, :KEEPALIVE, 2)
    assert_equal(true, opt.bool)
  end
end
