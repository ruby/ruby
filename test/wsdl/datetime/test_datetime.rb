require 'test/unit'
require 'soap/wsdlDriver'
require 'DatetimeService.rb'


module WSDL
module Datetime


class TestDatetime < Test::Unit::TestCase
  DIR = File.dirname(File.expand_path(__FILE__))

  Port = 17171

  def setup
    setup_server
    setup_client
  end

  def setup_server
    @server = DatetimePortTypeApp.new('Datetime server', nil, '0.0.0.0', Port)
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
  end

  def setup_client
    wsdl = File.join(DIR, 'datetime.wsdl')
    @client = ::SOAP::WSDLDriverFactory.new(wsdl).create_driver
    @client.endpoint_url = "http://localhost:#{Port}/"
    @client.generate_explicit_type = true
  end

  def teardown
    teardown_server
    teardown_client
  end

  def teardown_server
    @server.shutdown
    @t.kill
    @t.join
  end

  def teardown_client
    @client.reset_stream
  end

  def test_datetime
    d = DateTime.now
    d1 = d + 1
    d2 = @client.now(d)
    assert_equal(d1.year, d2.year)
    assert_equal(d1.month, d2.month)
    assert_equal(d1.day, d2.day)
    assert_equal(d1.hour, d2.hour)
    assert_equal(d1.min, d2.min)
    assert_equal(d1.sec, d2.sec)
    assert_equal(d1.sec, d2.sec)
  end

  def test_time
    d = DateTime.now
    t = Time.gm(d.year, d.month, d.day, d.hour, d.min, d.sec)
    d1 = d + 1
    d2 = @client.now(t)
    assert_equal(d1.year, d2.year)
    assert_equal(d1.month, d2.month)
    assert_equal(d1.day, d2.day)
    assert_equal(d1.hour, d2.hour)
    assert_equal(d1.min, d2.min)
    assert_equal(d1.sec, d2.sec)
    assert_equal(d1.sec, d2.sec)
  end
end


end
end
