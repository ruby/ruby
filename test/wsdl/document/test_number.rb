require 'test/unit'
require 'wsdl/parser'
require 'wsdl/soap/wsdl2ruby'
require 'soap/rpc/standaloneServer'
require 'soap/wsdlDriver'


module WSDL; module Document


class TestNumber < Test::Unit::TestCase
  class Server < ::SOAP::RPC::StandaloneServer
    Namespace = 'urn:foo'

    def on_init
      add_document_method(
        self,
        Namespace + ':get_foo',
        'get_foo',
        XSD::QName.new(Namespace, 'get_foo'),
        XSD::QName.new(Namespace, 'get_foo_response')
      )
    end

    def get_foo(arg)
      arg.number
    end
  end

  DIR = File.dirname(File.expand_path(__FILE__))
  Port = 17171

  def setup
    setup_server
    setup_classdef
    @client = nil
  end

  def teardown
    teardown_server
    File.unlink(pathname('foo.rb'))
    @client.reset_stream if @client
  end

  def setup_server
    @server = Server.new('Test', "urn:rpc", '0.0.0.0', Port)
    @server.level = Logger::Severity::ERROR
    @server_thread = start_server_thread(@server)
  end

  def setup_classdef
    gen = WSDL::SOAP::WSDL2Ruby.new
    gen.location = pathname("number.wsdl")
    gen.basedir = DIR
    gen.logger.level = Logger::FATAL
    gen.opt['classdef'] = nil
    gen.opt['force'] = true
    gen.run
    require pathname('foo')
  end

  def teardown_server
    @server.shutdown
    @server_thread.kill
    @server_thread.join
  end

  def start_server_thread(server)
    t = Thread.new {
      Thread.current.abort_on_exception = true
      server.start
    }
    t
  end

  def pathname(filename)
    File.join(DIR, filename)
  end

  def test_wsdl
    wsdl = File.join(DIR, 'number.wsdl')
    @client = ::SOAP::WSDLDriverFactory.new(wsdl).create_rpc_driver
    @client.endpoint_url = "http://localhost:#{Port}/"
    @client.wiredump_dev = STDOUT if $DEBUG

    # with the Struct defined in foo.rb, which is generated from WSDL
    assert_equal("12345", @client.get_foo(Get_foo.new("12345")))

    # with Hash
    assert_equal("12345", @client.get_foo({:number => "12345"}))

    # with Original struct
    get_foo_struct = Struct.new(:number)
    assert_equal("12345", @client.get_foo(get_foo_struct.new("12345")))
  end
end


end; end
