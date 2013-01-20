require "tempfile"

require "rss-testcase"

require "rss/1.0"
require "rss/dublincore"

module RSS
  class TestParser < TestCase
    def setup
      @_default_parser = Parser.default_parser
      @rss10 = make_RDF(<<-EOR)
#{make_channel}
#{make_item}
#{make_textinput}
#{make_image}
EOR
      @rss_tmp = Tempfile.new(%w"rss10- .rdf")
      @rss_tmp.print(@rss10)
      @rss_tmp.close
      @rss_file = @rss_tmp.path.untaint.trust
    end

    def teardown
      Parser.default_parser = @_default_parser
      @rss_tmp.close(true)
    end

    def test_default_parser
      assert_nothing_raised do
        Parser.default_parser = RSS::AVAILABLE_PARSERS.first
      end

      assert_raise(RSS::NotValidXMLParser) do
        Parser.default_parser = RSS::Parser
      end
    end

    def test_parse
      assert_not_nil(RSS::Parser.parse(@rss_file))

      garbage_rss_file = @rss_file + "-garbage"
      if RSS::Parser.default_parser.name == "RSS::XMLParserParser"
        assert_raise(RSS::NotWellFormedError) do
          RSS::Parser.parse(garbage_rss_file)
        end
      else
        assert_nil(RSS::Parser.parse(garbage_rss_file))
      end
    end

    def test_parse_tag_includes_hyphen
      assert_nothing_raised do
        RSS::Parser.parse(make_RDF(<<-EOR))
<xCal:x-calconnect-venue xmlns:xCal="urn:ietf:params:xml:ns:xcal" />
#{make_channel}
#{make_item}
#{make_textinput}
#{make_image}
EOR
      end
    end
  end
end
