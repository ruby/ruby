require 'test/unit'
require 'wsdl/parser'
require 'wsdl/soap/wsdl2ruby'
require 'soap/rpc/standaloneServer'
require 'soap/wsdlDriver'


module WSDL; module RPC


class TestRPC < Test::Unit::TestCase
  class Server < ::SOAP::RPC::StandaloneServer
    def on_init
      self.generate_explicit_type = false
      add_rpc_method(self, 'echo', 'arg1', 'arg2')
      add_rpc_method(self, 'echo_err', 'arg1', 'arg2')
    end

    DummyPerson = Struct.new("family-name".intern, :given_name)
    def echo(arg1, arg2)
      case arg1.family_name
      when 'normal'
        arg1.family_name = arg2.family_name
        arg1.given_name = arg2.given_name
        arg1.age = arg2.age
        arg1
      when 'dummy'
        DummyPerson.new("family-name", "given_name")
      else
        raise
      end
    end

    ErrPerson = Struct.new(:given_name, :no_such_element)
    def echo_err(arg1, arg2)
      ErrPerson.new(58, Time.now)
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
    File.unlink(pathname('echo.rb'))
    @client.reset_stream if @client
  end

  def setup_server
    @server = Server.new('Test', "urn:rpc", '0.0.0.0', Port)
    @server.level = Logger::Severity::ERROR
    @server_thread = start_server_thread(@server)
  end

  def setup_classdef
    gen = WSDL::SOAP::WSDL2Ruby.new
    gen.location = pathname("rpc.wsdl")
    gen.basedir = DIR
    gen.logger.level = Logger::FATAL
    gen.opt['classdef'] = nil
    gen.opt['force'] = true
    gen.run
    require pathname('echo')
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
    wsdl = File.join(DIR, 'rpc.wsdl')
    @client = ::SOAP::WSDLDriverFactory.new(wsdl).create_rpc_driver
    @client.endpoint_url = "http://localhost:#{Port}/"
    @client.wiredump_dev = STDOUT if $DEBUG

    ret = @client.echo(Person.new("normal", "", 12), Person.new("Hi", "Na", 21))
    assert_equal(Person, ret.class)
    assert_equal("Hi", ret.family_name)
    assert_equal("Na", ret.given_name)
    assert_equal(21, ret.age)

    ret = @client.echo(Person.new("dummy", "", 12), Person.new("Hi", "Na", 21))
    assert_equal(Person, ret.class)
    assert_equal("family-name", ret.family_name)
    assert_equal("given_name", ret.given_name)
    assert_equal(nil, ret.age)

    ret = @client.echo_err(Person.new("Na", "Hi"), Person.new("Hi", "Na"))
    assert_equal(Person, ret.class)
    assert_equal("58", ret.given_name)
    assert_equal(nil, ret.family_name)
    assert_equal(nil, ret.age)
  end
end


end; end
