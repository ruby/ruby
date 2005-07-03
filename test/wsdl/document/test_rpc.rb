require 'test/unit'
require 'wsdl/parser'
require 'wsdl/soap/wsdl2ruby'
require 'soap/rpc/standaloneServer'
require 'soap/wsdlDriver'


module WSDL; module Document


class TestRPC < Test::Unit::TestCase
  class Server < ::SOAP::RPC::StandaloneServer
    Namespace = 'urn:docrpc'

    def on_init
      add_document_method(
        self,
        Namespace + ':echo',
        'echo',
        XSD::QName.new(Namespace, 'echo'),
        XSD::QName.new(Namespace, 'echo_response')
      )
    end
  
    def echo(arg)
      if arg.is_a?(Echoele)
        # swap args
        tmp = arg.struct1
        arg.struct1 = arg.struct_2
        arg.struct_2 = tmp
        arg
      else
        # swap args
        tmp = arg["struct1"]
        arg["struct1"] = arg["struct-2"]
        arg["struct-2"] = tmp
        arg
      end
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
    #File.unlink(pathname('echo.rb'))
    @client.reset_stream if @client
  end

  def setup_server
    @server = Server.new('Test', "urn:rpc", '0.0.0.0', Port)
    @server.level = Logger::Severity::ERROR
    @server_thread = start_server_thread(@server)
  end

  def setup_classdef
    gen = WSDL::SOAP::WSDL2Ruby.new
    gen.location = pathname("document.wsdl")
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
    wsdl = File.join(DIR, 'document.wsdl')
    @client = ::SOAP::WSDLDriverFactory.new(wsdl).create_rpc_driver
    @client.endpoint_url = "http://localhost:#{Port}/"
    @client.wiredump_dev = STDOUT if $DEBUG

    struct1 = Echo_struct.new("mystring1", now1 = Time.now)
    struct1.xmlattr_m_attr = 'myattr1'
    struct2 = Echo_struct.new("mystring2", now2 = Time.now)
    struct2.xmlattr_m_attr = 'myattr2'
    echo = Echoele.new(struct1, struct2)
    echo.xmlattr_attr_string = 'attr_string'
    echo.xmlattr_attr_int = 5
    ret = @client.echo(echo)

    # struct#m_datetime in a response is a DateTime even though
    # struct#m_datetime in a request is a Time.
    timeformat = "%Y-%m-%dT%H:%M:%S"
    assert_equal("mystring2", ret.struct1.m_string)
    assert_equal(now2.strftime(timeformat),
      date2time(ret.struct1.m_datetime).strftime(timeformat))
    assert_equal("mystring1", ret.struct_2.m_string)
    assert_equal(now1.strftime(timeformat),
      date2time(ret.struct_2.m_datetime).strftime(timeformat))
    assert_equal("attr_string", ret.xmlattr_attr_string)
    assert_equal(5, ret.xmlattr_attr_int)
  end

  def date2time(date)
    if date.respond_to?(:to_time)
      date.to_time
    else
      d = date.new_offset(0)
      d.instance_eval {
        Time.utc(year, mon, mday, hour, min, sec,
          (sec_fraction * 86400000000).to_i)
      }.getlocal
    end
  end

  include ::SOAP
  def test_naive
    @client = ::SOAP::RPC::Driver.new("http://localhost:#{Port}/")
    @client.add_document_method('echo', 'urn:docrpc:echo',
      XSD::QName.new('urn:docrpc', 'echoele'),
      XSD::QName.new('urn:docrpc', 'echo_response'))
    @client.wiredump_dev = STDOUT if $DEBUG

    echo = SOAPElement.new('foo')
    echo.extraattr['attr_string'] = 'attr_string'
    echo.extraattr['attr-int'] = 5
    echo.add(struct1 = SOAPElement.new('struct1'))
    struct1.add(SOAPElement.new('m_string', 'mystring1'))
    struct1.add(SOAPElement.new('m_datetime', '2005-03-17T19:47:31+01:00'))
    struct1.extraattr['m_attr'] = 'myattr1'
    echo.add(struct2 = SOAPElement.new('struct-2'))
    struct2.add(SOAPElement.new('m_string', 'mystring2'))
    struct2.add(SOAPElement.new('m_datetime', '2005-03-17T19:47:32+02:00'))
    struct2.extraattr['m_attr'] = 'myattr2'
    ret = @client.echo(echo)
    timeformat = "%Y-%m-%dT%H:%M:%S"
    assert_equal('mystring2', ret.struct1.m_string)
    assert_equal('2005-03-17T19:47:32',
      ret.struct1.m_datetime.strftime(timeformat))
    assert_equal("mystring1", ret.struct_2.m_string)
    assert_equal('2005-03-17T19:47:31',
      ret.struct_2.m_datetime.strftime(timeformat))
    assert_equal('attr_string', ret.xmlattr_attr_string)
    assert_equal(5, ret.xmlattr_attr_int)

    echo = {'struct1' => {'m_string' => 'mystring1', 'm_datetime' => '2005-03-17T19:47:31+01:00'}, 
          'struct-2' => {'m_string' => 'mystring2', 'm_datetime' => '2005-03-17T19:47:32+02:00'}}
    ret = @client.echo(echo)
    timeformat = "%Y-%m-%dT%H:%M:%S"
    assert_equal('mystring2', ret.struct1.m_string)
    assert_equal('2005-03-17T19:47:32',
      ret.struct1.m_datetime.strftime(timeformat))
    assert_equal("mystring1", ret.struct_2.m_string)
    assert_equal('2005-03-17T19:47:31',
      ret.struct_2.m_datetime.strftime(timeformat))
  end
end


end; end
