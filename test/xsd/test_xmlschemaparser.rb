require 'test/unit'
require 'wsdl/xmlSchema/parser'

class TestXMLSchemaParser < Test::Unit::TestCase
  def self.setup(filename)
    @@filename = filename
  end

  def test_wsdl
    @wsdl = WSDL::XMLSchema::Parser.new.parse(File.open(@@filename).read)
  end
end

TestXMLSchemaParser.setup(File.join(File.dirname(__FILE__), 'xmlschema.xml'))
