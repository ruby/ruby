require 'test/unit'
require 'wsdl/xmlSchema/parser'


module XSD


class TestEmptyCharset < Test::Unit::TestCase
  def setup
    @file = File.join(File.dirname(File.expand_path(__FILE__)), 'noencoding.xml')
  end

  def test_wsdl
    begin
      xml = WSDL::XMLSchema::Parser.new.parse(File.open(@file) { |f| f.read })
    rescue Errno::EINVAL
      # unsupported encoding
      return
    end
    assert_equal(WSDL::XMLSchema::Schema, xml.class)
    assert_equal(0, xml.collect_elements.size)
  end
end


end
