require 'test/unit'
require 'wsdl/soap/wsdl2ruby'
require 'soap/rpc/standaloneServer'
require 'soap/wsdlDriver'

if defined?(HTTPAccess2) and defined?(OpenSSL)

module WSDL; module RPC


class TestRPCLIT < Test::Unit::TestCase
  class Server < ::SOAP::RPC::StandaloneServer
    Namespace = "http://soapbuilders.org/rpc-lit-test"

    def on_init
      self.generate_explicit_type = false
      add_rpc_operation(self, 
        XSD::QName.new(Namespace, 'echoStringArray'),
        nil,
        'echoStringArray', [
          ['in', 'inputStringArray', nil],
          ['retval', 'return', nil]
        ],
        {
          :request_style => :rpc,
          :request_use => :literal,
          :response_style => :rpc,
          :response_use => :literal
        }
      )
      add_rpc_operation(self, 
        XSD::QName.new(Namespace, 'echoStringArrayInline'),
        nil,
        'echoStringArrayInline', [
          ['in', 'inputStringArray', nil],
          ['retval', 'return', nil]
        ],
        {
          :request_style => :rpc,
          :request_use => :literal,
          :response_style => :rpc,
          :response_use => :literal
        }
      )
      add_rpc_operation(self, 
        XSD::QName.new(Namespace, 'echoNestedStruct'),
        nil,
        'echoNestedStruct', [
          ['in', 'inputNestedStruct', nil],
          ['retval', 'return', nil]
        ],
        {
          :request_style => :rpc,
          :request_use => :literal,
          :response_style => :rpc,
          :response_use => :literal
        }
      )
      add_rpc_operation(self, 
        XSD::QName.new(Namespace, 'echoStructArray'),
        nil,
        'echoStructArray', [
          ['in', 'inputStructArray', nil],
          ['retval', 'return', nil]
        ],
        {
          :request_style => :rpc,
          :request_use => :literal,
          :response_style => :rpc,
          :response_use => :literal
        }
      )
    end
  
    def echoStringArray(strings)
      # strings.stringItem => Array
      ArrayOfstring[*strings.stringItem]
    end

    def echoStringArrayInline(strings)
      ArrayOfstringInline[*strings.stringItem]
    end

    def echoNestedStruct(struct)
      struct
    end

    def echoStructArray(ary)
      ary
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
    unless $DEBUG
      File.unlink(pathname('RPC-Literal-TestDefinitions.rb'))
      File.unlink(pathname('RPC-Literal-TestDefinitionsDriver.rb'))
    end
    @client.reset_stream if @client
  end

  def setup_server
    @server = Server.new('Test', Server::Namespace, '0.0.0.0', Port)
    @server.level = Logger::Severity::ERROR
    @server_thread = start_server_thread(@server)
  end

  def setup_classdef
    gen = WSDL::SOAP::WSDL2Ruby.new
    gen.location = pathname("test-rpc-lit.wsdl")
    gen.basedir = DIR
    gen.logger.level = Logger::FATAL
    gen.opt['classdef'] = nil
    gen.opt['driver'] = nil
    gen.opt['force'] = true
    gen.run
    backupdir = Dir.pwd
    begin
      Dir.chdir(DIR)
      require pathname('RPC-Literal-TestDefinitions.rb')
      require pathname('RPC-Literal-TestDefinitionsDriver.rb')
    ensure
      Dir.chdir(backupdir)
    end
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

  def test_wsdl_echoStringArray
    wsdl = pathname('test-rpc-lit.wsdl')
    @client = ::SOAP::WSDLDriverFactory.new(wsdl).create_rpc_driver
    @client.endpoint_url = "http://localhost:#{Port}/"
    @client.wiredump_dev = STDOUT if $DEBUG
    # response contains only 1 part.
    result = @client.echoStringArray(ArrayOfstring["a", "b", "c"])[0]
    assert_equal(["a", "b", "c"], result.stringItem)
  end

  ECHO_STRING_ARRAY_REQUEST =
%q[<?xml version="1.0" encoding="utf-8" ?>
<env:Envelope xmlns:xsd="http://www.w3.org/2001/XMLSchema"
    xmlns:env="http://schemas.xmlsoap.org/soap/envelope/"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <env:Body>
    <n1:echoStringArray xmlns:n1="http://soapbuilders.org/rpc-lit-test">
      <inputStringArray xmlns:n2="http://soapbuilders.org/rpc-lit-test/types">
        <n2:stringItem>a</n2:stringItem>
        <n2:stringItem>b</n2:stringItem>
        <n2:stringItem>c</n2:stringItem>
      </inputStringArray>
    </n1:echoStringArray>
  </env:Body>
</env:Envelope>]

  ECHO_STRING_ARRAY_RESPONSE =
%q[<?xml version="1.0" encoding="utf-8" ?>
<env:Envelope xmlns:env="http://schemas.xmlsoap.org/soap/envelope/"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <env:Body>
    <n1:echoStringArrayResponse xmlns:n1="http://soapbuilders.org/rpc-lit-test">
      <return xmlns:n2="http://soapbuilders.org/rpc-lit-test/types">
        <n2:stringItem>a</n2:stringItem>
        <n2:stringItem>b</n2:stringItem>
        <n2:stringItem>c</n2:stringItem>
      </return>
    </n1:echoStringArrayResponse>
  </env:Body>
</env:Envelope>]

  def test_stub_echoStringArray
    drv = SoapTestPortTypeRpc.new("http://localhost:#{Port}/")
    drv.wiredump_dev = str = ''
    # response contains only 1 part.
    result = drv.echoStringArray(ArrayOfstring["a", "b", "c"])[0]
    assert_equal(["a", "b", "c"], result.stringItem)
    assert_equal(ECHO_STRING_ARRAY_REQUEST, parse_requestxml(str))
    assert_equal(ECHO_STRING_ARRAY_RESPONSE, parse_responsexml(str))
  end

  ECHO_STRING_ARRAY_INLINE_REQUEST =
%q[<?xml version="1.0" encoding="utf-8" ?>
<env:Envelope xmlns:xsd="http://www.w3.org/2001/XMLSchema"
    xmlns:env="http://schemas.xmlsoap.org/soap/envelope/"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <env:Body>
    <n1:echoStringArrayInline xmlns:n1="http://soapbuilders.org/rpc-lit-test">
      <inputStringArray>
        <stringItem>a</stringItem>
        <stringItem>b</stringItem>
        <stringItem>c</stringItem>
      </inputStringArray>
    </n1:echoStringArrayInline>
  </env:Body>
</env:Envelope>]

  ECHO_STRING_ARRAY_INLINE_RESPONSE =
%q[<?xml version="1.0" encoding="utf-8" ?>
<env:Envelope xmlns:env="http://schemas.xmlsoap.org/soap/envelope/"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <env:Body>
    <n1:echoStringArrayInlineResponse xmlns:n1="http://soapbuilders.org/rpc-lit-test">
      <return>
        <stringItem>a</stringItem>
        <stringItem>b</stringItem>
        <stringItem>c</stringItem>
      </return>
    </n1:echoStringArrayInlineResponse>
  </env:Body>
</env:Envelope>]

  def test_stub_echoStringArrayInline
    drv = SoapTestPortTypeRpc.new("http://localhost:#{Port}/")
    drv.wiredump_dev = str = ''
    # response contains only 1 part.
    result = drv.echoStringArrayInline(ArrayOfstringInline["a", "b", "c"])[0]
    assert_equal(["a", "b", "c"], result.stringItem)
    assert_equal(ECHO_STRING_ARRAY_INLINE_REQUEST, parse_requestxml(str))
    assert_equal(ECHO_STRING_ARRAY_INLINE_RESPONSE, parse_responsexml(str))
  end

  ECHO_NESTED_STRUCT_REQUEST =
%q[<?xml version="1.0" encoding="utf-8" ?>
<env:Envelope xmlns:xsd="http://www.w3.org/2001/XMLSchema"
    xmlns:env="http://schemas.xmlsoap.org/soap/envelope/"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <env:Body>
    <n1:echoNestedStruct xmlns:n1="http://soapbuilders.org/rpc-lit-test">
      <inputStruct xmlns:n2="http://soapbuilders.org/rpc-lit-test/types">
        <varString>str</varString>
        <varInt>1</varInt>
        <varFloat>+1</varFloat>
        <n2:structItem>
          <varString>str</varString>
          <varInt>1</varInt>
          <varFloat>+1</varFloat>
        </n2:structItem>
      </inputStruct>
    </n1:echoNestedStruct>
  </env:Body>
</env:Envelope>]

  ECHO_NESTED_STRUCT_RESPONSE =
%q[<?xml version="1.0" encoding="utf-8" ?>
<env:Envelope xmlns:env="http://schemas.xmlsoap.org/soap/envelope/"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <env:Body>
    <n1:echoNestedStructResponse xmlns:n1="http://soapbuilders.org/rpc-lit-test">
      <return xmlns:n2="http://soapbuilders.org/rpc-lit-test/types">
        <varString>str</varString>
        <varInt>1</varInt>
        <varFloat>+1</varFloat>
        <n2:structItem>
          <varString>str</varString>
          <varInt>1</varInt>
          <varFloat>+1</varFloat>
        </n2:structItem>
      </return>
    </n1:echoNestedStructResponse>
  </env:Body>
</env:Envelope>]

  def test_wsdl_echoNestedStruct
    wsdl = pathname('test-rpc-lit.wsdl')
    @client = ::SOAP::WSDLDriverFactory.new(wsdl).create_rpc_driver
    @client.endpoint_url = "http://localhost:#{Port}/"
    @client.wiredump_dev = str = ''
    # response contains only 1 part.
    result = @client.echoNestedStruct(SOAPStructStruct.new("str", 1, 1.0, SOAPStruct.new("str", 1, 1.0)))[0]
    assert_equal('str', result.varString)
    assert_equal('1', result.varInt)
    assert_equal('+1', result.varFloat)
    assert_equal('str', result.structItem.varString)
    assert_equal('1', result.structItem.varInt)
    assert_equal('+1', result.structItem.varFloat)
    assert_equal(ECHO_NESTED_STRUCT_REQUEST, parse_requestxml(str))
    assert_equal(ECHO_NESTED_STRUCT_RESPONSE, parse_responsexml(str))
  end

  def test_stub_echoNestedStruct
    drv = SoapTestPortTypeRpc.new("http://localhost:#{Port}/")
    drv.wiredump_dev = str = ''
    # response contains only 1 part.
    result = drv.echoNestedStruct(SOAPStructStruct.new("str", 1, 1.0, SOAPStruct.new("str", 1, 1.0)))[0]
    assert_equal('str', result.varString)
    assert_equal('1', result.varInt)
    assert_equal('+1', result.varFloat)
    assert_equal('str', result.structItem.varString)
    assert_equal('1', result.structItem.varInt)
    assert_equal('+1', result.structItem.varFloat)
    assert_equal(ECHO_NESTED_STRUCT_REQUEST, parse_requestxml(str))
    assert_equal(ECHO_NESTED_STRUCT_RESPONSE, parse_responsexml(str))
  end

  ECHO_STRUCT_ARRAY_REQUEST =
%q[<?xml version="1.0" encoding="utf-8" ?>
<env:Envelope xmlns:xsd="http://www.w3.org/2001/XMLSchema"
    xmlns:env="http://schemas.xmlsoap.org/soap/envelope/"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <env:Body>
    <n1:echoStructArray xmlns:n1="http://soapbuilders.org/rpc-lit-test">
      <inputStructArray xmlns:n2="http://soapbuilders.org/rpc-lit-test/types">
        <n2:structItem>
          <varString>str</varString>
          <varInt>2</varInt>
          <varFloat>+2.1</varFloat>
        </n2:structItem>
        <n2:structItem>
          <varString>str</varString>
          <varInt>2</varInt>
          <varFloat>+2.1</varFloat>
        </n2:structItem>
      </inputStructArray>
    </n1:echoStructArray>
  </env:Body>
</env:Envelope>]

  ECHO_STRUCT_ARRAY_RESPONSE =
%q[<?xml version="1.0" encoding="utf-8" ?>
<env:Envelope xmlns:env="http://schemas.xmlsoap.org/soap/envelope/"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <env:Body>
    <n1:echoStructArrayResponse xmlns:n1="http://soapbuilders.org/rpc-lit-test">
      <return xmlns:n2="http://soapbuilders.org/rpc-lit-test/types">
        <n2:structItem>
          <varString>str</varString>
          <varInt>2</varInt>
          <varFloat>+2.1</varFloat>
        </n2:structItem>
        <n2:structItem>
          <varString>str</varString>
          <varInt>2</varInt>
          <varFloat>+2.1</varFloat>
        </n2:structItem>
      </return>
    </n1:echoStructArrayResponse>
  </env:Body>
</env:Envelope>]

  def test_wsdl_echoStructArray
    wsdl = pathname('test-rpc-lit.wsdl')
    @client = ::SOAP::WSDLDriverFactory.new(wsdl).create_rpc_driver
    @client.endpoint_url = "http://localhost:#{Port}/"
    @client.wiredump_dev = str = ''
    # response contains only 1 part.
    e = SOAPStruct.new("str", 2, 2.1)
    result = @client.echoStructArray(ArrayOfSOAPStruct[e, e])
    assert_equal(ECHO_STRUCT_ARRAY_REQUEST, parse_requestxml(str))
    assert_equal(ECHO_STRUCT_ARRAY_RESPONSE, parse_responsexml(str))
  end

  def test_stub_echoStructArray
    drv = SoapTestPortTypeRpc.new("http://localhost:#{Port}/")
    drv.wiredump_dev = str = ''
    # response contains only 1 part.
    e = SOAPStruct.new("str", 2, 2.1)
    result = drv.echoStructArray(ArrayOfSOAPStruct[e, e])
    assert_equal(ECHO_STRUCT_ARRAY_REQUEST, parse_requestxml(str))
    assert_equal(ECHO_STRUCT_ARRAY_RESPONSE, parse_responsexml(str))
  end

  def parse_requestxml(str)
    str.split(/\r?\n\r?\n/)[3]
  end

  def parse_responsexml(str)
    str.split(/\r?\n\r?\n/)[6]
  end
end


end; end

end
