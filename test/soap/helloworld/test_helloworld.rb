require 'test/unit'
require 'soap/rpc/driver'

dir = File.dirname(__FILE__)
$:.push(dir)
require 'hw_s.rb'
$:.delete(dir)


module SOAP
module HelloWorld


class TestHelloWorld < Test::Unit::TestCase
  def setup
    @server = HelloWorldServer.new('hws', 'urn:hws', '0.0.0.0', 2000)
    @t = Thread.new {
      @server.start
    }
    while @server.server.status != :Running
      sleep 0.1
    end
    @client = SOAP::RPC::Driver.new('http://localhost:2000/', 'urn:hws')
    @client.add_method("hello_world", "from")
  end

  def teardown
    @server.server.shutdown
    @t.kill
  end

  def test_hello_world
    assert_equal("Hello World, from NaHi", @client.hello_world("NaHi"))
    assert_equal("Hello World, from <&>", @client.hello_world("<&>"))
  end
end


end
end
