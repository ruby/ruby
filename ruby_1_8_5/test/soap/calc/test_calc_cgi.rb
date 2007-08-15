require 'test/unit'
require 'soap/rpc/driver'
require 'logger'
require 'webrick'
require 'rbconfig'


module SOAP
module Calc


class TestCalcCGI < Test::Unit::TestCase
  # This test shuld be run after installing ruby.
  RUBYBIN = File.join(
    Config::CONFIG["bindir"],
    Config::CONFIG["ruby_install_name"] + Config::CONFIG["EXEEXT"]
  )
  RUBYBIN << " -d" if $DEBUG

  Port = 17171

  def setup
    logger = Logger.new(STDERR)
    logger.level = Logger::Severity::ERROR
    @server = WEBrick::HTTPServer.new(
      :BindAddress => "0.0.0.0",
      :Logger => logger,
      :Port => Port,
      :AccessLog => [],
      :DocumentRoot => File.dirname(File.expand_path(__FILE__)),
      :CGIPathEnv => ENV['PATH'],
      :CGIInterpreter => RUBYBIN
    )
    @t = Thread.new {
      Thread.current.abort_on_exception = true
      @server.start
    }
    @endpoint = "http://localhost:#{Port}/server.cgi"
    @calc = SOAP::RPC::Driver.new(@endpoint, 'http://tempuri.org/calcService')
    @calc.wiredump_dev = STDERR if $DEBUG
    @calc.add_method('add', 'lhs', 'rhs')
    @calc.add_method('sub', 'lhs', 'rhs')
    @calc.add_method('multi', 'lhs', 'rhs')
    @calc.add_method('div', 'lhs', 'rhs')
  end

  def teardown
    @server.shutdown
    @t.kill
    @t.join
    @calc.reset_stream
  end

  def test_calc_cgi
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
