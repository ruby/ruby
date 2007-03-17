begin
  require "fileutils"
rescue LoadError
  module FileUtils
    module_function
    def rm_f(target)
      File.unlink(target)
    rescue Errno::ENOENT
    end
  end
end

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
      @rss_file = "rss10.rdf"
      File.open(@rss_file, "w") {|f| f.print(@rss10)}
    end
    
    def teardown
      Parser.default_parser = @_default_parser
      FileUtils.rm_f(@rss_file)
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
  end
end
