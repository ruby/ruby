require 'test/unit'
require 'soap/rpc/driver'

dir = File.dirname(__FILE__)
$:.push(dir)
require 'server.rb'
$:.delete(dir)


module SOAP
module Calc


class TestCalc < Test::Unit::TestCase
  Port = 17171

  def setup
    @server = CalcServer.new(self.class.name, nil, '0.0.0.0', Port)
    @server.level = Logger::Severity::FATAL
    @t = Thread.new {
      @server.start
    }
    while @server.server.nil? or @server.server.status != :Running
      sleep 0.1
    end
    @calc = SOAP::RPC::Driver.new("http://localhost:#{Port}/", 'http://tempuri.org/calcService')
    @calc.add_method('add', 'lhs', 'rhs')
    @calc.add_method('sub', 'lhs', 'rhs')
    @calc.add_method('multi', 'lhs', 'rhs')
    @calc.add_method('div', 'lhs', 'rhs')
  end

  def teardown
    @server.server.shutdown
    @t.kill
  end

  def test_calc
    assert_equal(3, @calc.add(1, 2))
    assert_equal(-1.1, @calc.sub(1.1, 2.2))
    assert_equal(2.42, @calc.multi(1.1, 2.2))
    assert_equal(2, @calc.div(5, 2))
    assert_equal(2.5, @calc.div(5.0, 2))
    assert_equal(1.0/0.0, @calc.div(1.1, 0))
    assert_raises(ZeroDivisionError) do
      @calc.div(1, 0)
    end
  end
end


end
end
