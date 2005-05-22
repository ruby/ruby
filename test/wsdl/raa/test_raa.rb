require 'test/unit'
require 'soap/wsdlDriver'
require 'RAA.rb'
require 'RAAServant.rb'
require 'RAAService.rb'


module WSDL
module RAA


class TestRAA < Test::Unit::TestCase
  DIR = File.dirname(File.expand_path(__FILE__))

  Port = 17171

  def setup
    setup_server
    setup_client
  end

  def setup_server
    @server = App.new('RAA server', nil, '0.0.0.0', Port)
    @server.level = Logger::Severity::ERROR
    @t = Thread.new {
      Thread.current.abort_on_exception = true
      @server.start
    }
  end

  def setup_client
    wsdl = File.join(DIR, 'raa.wsdl')
    @raa = ::SOAP::WSDLDriverFactory.new(wsdl).create_rpc_driver
    @raa.endpoint_url = "http://localhost:#{Port}/"
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
    @raa.reset_stream
  end

  def test_raa
    assert_equal(["ruby", "soap4r"], @raa.getAllListings)
  end

  def foo
    p @raa.getProductTree()
    p @raa.getInfoFromCategory(Category.new("Library", "XML"))
    t = Time.at(Time.now.to_i - 24 * 3600)
    p @raa.getModifiedInfoSince(t)
    p @raa.getModifiedInfoSince(DateTime.new(t.year, t.mon, t.mday, t.hour, t.min, t.sec))
    o = @raa.getInfoFromName("SOAP4R")
    p o.type
    p o.owner.name
    p o
  end
end


end
end
