require 'test/unit'
require 'soap/rpc/driver'
require 'server2.rb'


module SOAP
module Calc


class TestCalc2 < Test::Unit::TestCase
  Port = 17171

  def setup
    @server = CalcServer2.new('CalcServer', 'http://tempuri.org/calcService', '0.0.0.0', Port)
    @server.level = Logger::Severity::ERROR
    @t = Thread.new {
      Thread.current.abort_on_exception = true
      @server.start
    }
    while @server.status != :Running
      sleep 0.1
      unless @t.alive?
	@t.join
	raise
      end
    end
    @endpoint = "http://localhost:#{Port}/"
    @var = SOAP::RPC::Driver.new(@endpoint, 'http://tempuri.org/calcService')
    @var.wiredump_dev = STDERR if $DEBUG
    @var.add_method('set', 'newValue')
    @var.add_method('get')
    @var.add_method_as('+', 'add', 'rhs')
    @var.add_method_as('-', 'sub', 'rhs')
    @var.add_method_as('*', 'multi', 'rhs')
    @var.add_method_as('/', 'div', 'rhs')
  end

  def teardown
    @server.shutdown
    @t.kill
    @t.join
    @var.reset_stream
  end

  def test_calc2
    assert_equal(1, @var.set(1))
    assert_equal(3, @var + 2)
    assert_equal(-1.2, @var - 2.2)
    assert_equal(2.2, @var * 2.2)
    assert_equal(0, @var / 2)
    assert_equal(0.5, @var / 2.0)
    assert_raises(ZeroDivisionError) do
      @var / 0
    end
  end
end


end
end
