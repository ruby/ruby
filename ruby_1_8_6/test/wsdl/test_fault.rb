require 'test/unit'
require 'soap/processor'
require 'soap/mapping'
require 'soap/rpc/element'
require 'wsdl/parser'


module WSDL


class TestFault < Test::Unit::TestCase
  def setup
    @xml =<<__EOX__
<?xml version="1.0" encoding="utf-8" ?>
<env:Envelope xmlns:xsd="http://www.w3.org/2001/XMLSchema"
    xmlns:env="http://schemas.xmlsoap.org/soap/envelope/"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <env:Body>
    <env:Fault xmlns:n1="http://schemas.xmlsoap.org/soap/encoding/"
        env:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
      <faultcode xsi:type="xsd:string">Server</faultcode>
      <faultstring xsi:type="xsd:string">faultstring</faultstring>
      <faultactor xsi:type="xsd:string">faultactor</faultactor>
      <detail xmlns:n2="http://www.ruby-lang.org/xmlns/ruby/type/custom"
          xsi:type="n2:SOAPException">
	<excn_type_name xsi:type="xsd:string">type</excn_type_name>
	<cause href="#id123"/>
      </detail>
    </env:Fault>
    <cause id="id123" xsi:type="xsd:int">5</cause>
  </env:Body>
</env:Envelope>
__EOX__
  end

  def test_by_wsdl
    rpc_decode_typemap = WSDL::Definitions.soap_rpc_complextypes
    opt = {}
    opt[:default_encodingstyle] = ::SOAP::EncodingNamespace
    opt[:decode_typemap] = rpc_decode_typemap
    header, body = ::SOAP::Processor.unmarshal(@xml, opt)
    fault = ::SOAP::Mapping.soap2obj(body.response)
    assert_equal("Server", fault.faultcode)
    assert_equal("faultstring", fault.faultstring)
    assert_equal(URI.parse("faultactor"), fault.faultactor)
    assert_equal(5, fault.detail.cause)
  end
end


end
