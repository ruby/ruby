require 'test/unit'
require 'soap/wsdlDriver'


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
    $:.push(DIR)
    require File.join(DIR, 'DatetimeService.rb')
    $:.delete(DIR)
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
    d1 = DateTime.now
    d2 = @client.now(d1)
    assert_equal(d2.year, d1.year)
    assert_equal(d2.month, d1.month)
    assert_equal(d2.day, d1.day + 1)
    assert_equal(d2.hour, d1.hour)
    assert_equal(d2.min, d1.min)
    assert_equal(d2.sec, d1.sec)
    assert_equal(d2.sec, d1.sec)
  end

  def test_time
    d = DateTime.now
    t = Time.gm(d.year, d.month, d.day, d.hour, d.min, d.sec)
    d2 = d + 1
    t2 = @client.now(t)
    assert_equal(d2.year, t2.year)
    assert_equal(d2.month, t2.month)
    assert_equal(d2.day, t2.day)
    assert_equal(d2.hour, t2.hour)
    assert_equal(d2.min, t2.min)
    assert_equal(d2.sec, t2.sec)
  end
end


end
end
