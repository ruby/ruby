require 'test/unit'
require 'soap/processor'
require 'soap/mapping'
require 'soap/rpc/element'
require 'wsdl/importer'
require 'itemList.rb'


module WSDL


class TestAxisArray < Test::Unit::TestCase
  def setup
    @xml =<<__EOX__
<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <soapenv:Body>
    <ns1:listItemResponse soapenv:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:ns1="urn:jp.gr.jin.rrr.example.itemList">
      <list href="#id0"/>
    </ns1:listItemResponse>
    <multiRef id="id0" soapenc:root="0" soapenv:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xsi:type="ns2:ItemList" xmlns:soapenc="http://schemas.xmlsoap.org/soap/encoding/" xmlns:ns2="urn:jp.gr.jin.rrr.example.itemListType">
      <Item href="#id1"/>
      <Item href="#id2"/>
      <Item href="#id3"/>
    </multiRef>
    <multiRef id="id3" soapenc:root="0" soapenv:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xsi:type="ns3:Item" xmlns:ns3="urn:jp.gr.jin.rrr.example.itemListType" xmlns:soapenc="http://schemas.xmlsoap.org/soap/encoding/">
      <name xsi:type="xsd:string">name3</name>
    </multiRef>
    <multiRef id="id1" soapenc:root="0" soapenv:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xsi:type="ns4:Item" xmlns:ns4="urn:jp.gr.jin.rrr.example.itemListType" xmlns:soapenc="http://schemas.xmlsoap.org/soap/encoding/">
      <name xsi:type="xsd:string">name1</name>
    </multiRef>
    <multiRef id="id2" soapenc:root="0" soapenv:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xsi:type="ns5:Item" xmlns:ns5="urn:jp.gr.jin.rrr.example.itemListType" xmlns:soapenc="http://schemas.xmlsoap.org/soap/encoding/">
      <name xsi:type="xsd:string">name2</name>
    </multiRef>
  </soapenv:Body>
</soapenv:Envelope>
__EOX__
  end

  def test_by_stub
    header, body = ::SOAP::Processor.unmarshal(@xml)
    ary = ::SOAP::Mapping.soap2obj(body.response)
    assert_equal(3, ary.size)
    assert_equal("name1", ary[0].name)
    assert_equal("name2", ary[1].name)
    assert_equal("name3", ary[2].name)
  end

  def test_by_wsdl
    wsdlfile = File.join(File.dirname(File.expand_path(__FILE__)), 'axisArray.wsdl')
    wsdl = WSDL::Importer.import(wsdlfile)
    service = wsdl.services[0]
    port = service.ports[0]
    wsdl_types = wsdl.collect_complextypes
    rpc_decode_typemap = wsdl_types + wsdl.soap_rpc_complextypes(port.find_binding)
    opt = {}
    opt[:default_encodingstyle] = ::SOAP::EncodingNamespace
    opt[:decode_typemap] = rpc_decode_typemap
    header, body = ::SOAP::Processor.unmarshal(@xml, opt)
    ary = ::SOAP::Mapping.soap2obj(body.response)
    assert_equal(3, ary.size)
    assert_equal("name1", ary[0].name)
    assert_equal("name2", ary[1].name)
    assert_equal("name3", ary[2].name)
  end
end


end
