require 'test/unit/testcase'
require 'rexml/parsers/lightparser'

class LightParserTester < Test::Unit::TestCase
	include REXML
	def test_parsing
		f = File.new( "test/data/documentation.xml" )
		parser = REXML::Parsers::LightParser.new( f )
		root = parser.parse
	end
end
