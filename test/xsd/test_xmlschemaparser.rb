require 'test/unit'
require 'wsdl/xmlSchema/parser'


module XSD


class TestXMLSchemaParser < Test::Unit::TestCase
  def setup
    @file = File.join(File.dirname(File.expand_path(__FILE__)), 'xmlschema.xml')
  end

  def test_wsdl
    @wsdl = WSDL::XMLSchema::Parser.new.parse(File.open(@file) { |f| f.read })
    assert_equal(WSDL::XMLSchema::Schema, @wsdl.class)
    assert_equal(1, @wsdl.collect_elements.size)
  end
end



end
