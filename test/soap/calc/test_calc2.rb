require 'test/unit'
require 'soap/rpc/driver'

dir = File.dirname(__FILE__)
$:.push(dir)
require 'server2.rb'
$:.delete(dir)


module SOAP
module Calc


class TestCalc2 < Test::Unit::TestCase
  Port = 17171

  def setup
    @server = CalcServer2.new('CalcServer', 'http://tempuri.org/calcService', '0.0.0.0', Port)
    @server.level = Logger::Severity::FATAL
    @t = Thread.new {
      @server.start
    }
    while @server.server.nil? or @server.server.status != :Running
      sleep 0.1
    end
    @var = SOAP::RPC::Driver.new("http://localhost:#{Port}/", 'http://tempuri.org/calcService')
    @var.add_method('set', 'newValue')
    @var.add_method('get')
    @var.add_method_as('+', 'add', 'rhs')
    @var.add_method_as('-', 'sub', 'rhs')
    @var.add_method_as('*', 'multi', 'rhs')
    @var.add_method_as('/', 'div', 'rhs')
  end

  def teardown
    @server.server.shutdown
    @t.kill
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
