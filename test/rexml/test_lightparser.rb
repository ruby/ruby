# frozen_string_literal: false
require_relative 'rexml_test_utils'
require 'rexml/parsers/lightparser'

module REXMLTests
  class LightParserTester < Test::Unit::TestCase
    include REXMLTestUtils
    include REXML
    def test_parsing
      File.open(fixture_path("documentation.xml")) do |f|
        parser = REXML::Parsers::LightParser.new( f )
        parser.parse
      end
    end
  end
end
