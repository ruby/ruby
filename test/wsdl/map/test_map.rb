require 'test/unit'
require 'soap/processor'
require 'soap/mapping'
require 'soap/rpc/element'
require 'wsdl/importer'


module WSDL


class TestMap < Test::Unit::TestCase
  def setup
  end

  def test_by_wsdl
    dir = File.dirname(File.expand_path(__FILE__))
    wsdlfile = File.join(dir, 'map.wsdl')
    xml = File.open(File.join(dir, 'map.xml')) { |f| f.read }
    wsdl = WSDL::Importer.import(wsdlfile)
    service = wsdl.services[0]
    port = service.ports[0]
    wsdl_types = wsdl.collect_complextypes
    rpc_decode_typemap = wsdl_types + wsdl.soap_rpc_complextypes(port.find_binding)
    opt = {}
    opt[:default_encodingstyle] = ::SOAP::EncodingNamespace
    opt[:decode_typemap] = rpc_decode_typemap
    header, body = ::SOAP::Processor.unmarshal(xml, opt)
    map = ::SOAP::Mapping.soap2obj(body.response)
    assert_equal(["a1"], map["a"]["a1"])
    assert_equal(["a2"], map["a"]["a2"])
    assert_equal(["b1"], map["b"]["b1"])
    assert_equal(["b2"], map["b"]["b2"])
  end
end


end
