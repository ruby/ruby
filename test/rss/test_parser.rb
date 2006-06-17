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
require "rss/2.0"
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
    
    def test_RDF
      assert_ns("", RDF::URI) do
        Parser.parse(<<-EOR)
#{make_xmldecl}
<RDF/>
EOR
      end 

      assert_ns("", RDF::URI) do
        Parser.parse(<<-EOR)
#{make_xmldecl}
<RDF xmlns="hoge"/>
EOR
      end 

      assert_ns("rdf", RDF::URI) do
        Parser.parse(<<-EOR)
#{make_xmldecl}
<rdf:RDF xmlns:rdf="hoge"/>
EOR
      end

      assert_parse(<<-EOR, :missing_tag, "channel", "RDF")
#{make_xmldecl}
<rdf:RDF xmlns:rdf="#{RSS::RDF::URI}"/>
EOR

      assert_parse(<<-EOR, :missing_tag, "channel", "RDF")
#{make_xmldecl}
<RDF xmlns="#{RSS::RDF::URI}"/>
EOR

      assert_parse(<<-EOR, :missing_tag, "channel", "RDF")
#{make_xmldecl}
<RDF xmlns="#{RSS::RDF::URI}"/>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "item", "RDF")
#{make_channel}
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "item", "RDF")
#{make_channel}
#{make_image}
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "item", "RDF")
#{make_channel}
#{make_textinput}
EOR

      assert_too_much_tag("image", "RDF") do
        Parser.parse(make_RDF(<<-EOR))
#{make_channel}
#{make_image}
#{make_image}
#{make_item}
#{make_textinput}
EOR
      end

      assert_parse(make_RDF(<<-EOR), :nothing_raised)
#{make_channel}
#{make_item}
#{make_image}
#{make_textinput}
EOR

      assert_parse(make_RDF(<<-EOR), :nothing_raised)
#{make_channel}
#{make_item}
#{make_textinput}
#{make_image}
EOR

      assert_parse(make_RDF(<<-EOR), :nothing_raised)
#{make_channel}
#{make_image}
#{make_item}
EOR

      assert_parse(make_RDF(<<-EOR), :nothing_raised)
#{make_channel}
#{make_image}
#{make_item}
#{make_textinput}
EOR

      1.step(15, 3) do |i|
        rss = make_RDF() do
          res = make_channel
          i.times { res << make_item }
          res
        end
        assert_parse(rss, :nothing_raised)
      end
    end

    def test_undefined_entity
      return unless RSS::Parser.default_parser.raise_for_undefined_entity?
      assert_parse(make_RDF(<<-EOR), :raises, RSS::NotWellFormedError)
#{make_channel}
#{make_image}
<item rdf:about="#{RDF_ABOUT}">
  <title>#{TITLE_VALUE} &UNKNOWN_ENTITY;</title>
  <link>#{LINK_VALUE}</link>
  <description>#{DESCRIPTION_VALUE}</description>
</item>
#{make_textinput}
EOR
    end

    def test_channel

      assert_parse(make_RDF(<<-EOR), :missing_attribute, "channel", "rdf:about")
<channel />
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "title", "channel")
<channel rdf:about="http://example.com/"/>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "link", "channel")
<channel rdf:about="http://example.com/">
  <title>hoge</title>
</channel>
EOR

      assert_parse(make_RDF(<<EOR), :missing_tag, "description", "channel")
<channel rdf:about="http://example.com/">
  <title>hoge</title>
  <link>http://example.com/</link>
</channel>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "items", "channel")
<channel rdf:about="http://example.com/">
  <title>hoge</title>
  <link>http://example.com/</link>
  <description>hogehoge</description>
</channel>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_attribute, "image", "rdf:resource")
<channel rdf:about="http://example.com/">
  <title>hoge</title>
  <link>http://example.com/</link>
  <description>hogehoge</description>
  <image/>
</channel>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "items", "channel")
<channel rdf:about="http://example.com/">
  <title>hoge</title>
  <link>http://example.com/</link>
  <description>hogehoge</description>
  <image rdf:resource="http://example.com/hoge.png" />
</channel>
EOR

      rss = make_RDF(<<-EOR)
<channel rdf:about="http://example.com/">
  <title>hoge</title>
  <link>http://example.com/</link>
  <description>hogehoge</description>
  <image rdf:resource="http://example.com/hoge.png" />
  <items/>
</channel>
EOR

      assert_missing_tag("Seq", "items") do
        Parser.parse(rss)
      end

      assert_missing_tag("item", "RDF") do
        Parser.parse(rss, false).validate
      end

      assert_parse(make_RDF(<<-EOR), :missing_tag, "item", "RDF")
<channel rdf:about="http://example.com/">
  <title>hoge</title>
  <link>http://example.com/</link>
  <description>hogehoge</description>
  <image rdf:resource="http://example.com/hoge.png" />
  <items>
    <rdf:Seq>
    </rdf:Seq>
  </items>
</channel>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_attribute, "textinput", "rdf:resource")
<channel rdf:about="http://example.com/">
  <title>hoge</title>
  <link>http://example.com/</link>
  <description>hogehoge</description>
  <image rdf:resource="http://example.com/hoge.png" />
  <items>
    <rdf:Seq>
    </rdf:Seq>
  </items>
  <textinput/>
</channel>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "item", "RDF")
<channel rdf:about="http://example.com/">
  <title>hoge</title>
  <link>http://example.com/</link>
  <description>hogehoge</description>
  <image rdf:resource="http://example.com/hoge.png" />
  <items>
    <rdf:Seq>
    </rdf:Seq>
  </items>
  <textinput rdf:resource="http://example.com/search" />
</channel>
EOR

    end

    def test_rdf_li

      rss = make_RDF(<<-EOR)
<channel rdf:about="http://example.com/">
  <title>hoge</title>
  <link>http://example.com/</link>
  <description>hogehoge</description>
  <image rdf:resource="http://example.com/hoge.png" />
  <items>
    <rdf:Seq>
      <rdf:li \#{rdf_li_attr}/>
    </rdf:Seq>
  </items>
  <textinput rdf:resource="http://example.com/search" />
</channel>
#{make_item}
EOR

      source = Proc.new do |rdf_li_attr|
        eval(%Q[%Q[#{rss}]], binding)
      end

      attr = %q[resource="http://example.com/hoge"]
      assert_parse(source.call(attr), :nothing_raised)

      attr = %q[rdf:resource="http://example.com/hoge"]
      assert_parse(source.call(attr), :nothing_raised)

      assert_parse(source.call(""), :missing_attribute, "li", "resource")
    end

    def test_image

      assert_parse(make_RDF(<<-EOR), :missing_attribute, "image", "rdf:about")
#{make_channel}
<image>
</image>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "title", "image")
#{make_channel}
<image rdf:about="http://example.com/hoge.png">
</image>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "url", "image")
#{make_channel}
<image rdf:about="http://example.com/hoge.png">
  <title>hoge</title>
</image>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "link", "image")
#{make_channel}
<image rdf:about="http://example.com/hoge.png">
  <title>hoge</title>
  <url>http://example.com/hoge.png</url>
</image>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "item", "RDF")
#{make_channel}
<image rdf:about="http://example.com/hoge.png">
  <title>hoge</title>
  <url>http://example.com/hoge.png</url>
  <link>http://example.com/</link>
</image>
EOR

      rss = make_RDF(<<-EOR)
#{make_channel}
<image rdf:about="http://example.com/hoge.png">
  <link>http://example.com/</link>
  <url>http://example.com/hoge.png</url>
  <title>hoge</title>
</image>
EOR

      assert_missing_tag("item", "RDF") do
        Parser.parse(rss)
      end

      assert_missing_tag("item", "RDF") do
        Parser.parse(rss, false).validate
      end

    end

    def test_item

      assert_parse(make_RDF(<<-EOR), :missing_attribute, "item", "rdf:about")
#{make_channel}
#{make_image}
<item>
</item>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "title", "item")
#{make_channel}
#{make_image}
<item rdf:about="http://example.com/hoge.html">
</item>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "link", "item")
#{make_channel}
#{make_image}
<item rdf:about="http://example.com/hoge.html">
  <title>hoge</title>
</item>
EOR

      assert_too_much_tag("title", "item") do
        Parser.parse(make_RDF(<<-EOR))
#{make_channel}
#{make_image}
<item rdf:about="http://example.com/hoge.html">
  <title>hoge</title>
  <title>hoge</title>
  <link>http://example.com/hoge.html</link>
</item>
EOR
      end

      assert_parse(make_RDF(<<-EOR), :nothing_raised)
#{make_channel}
#{make_image}
<item rdf:about="http://example.com/hoge.html">
  <title>hoge</title>
  <link>http://example.com/hoge.html</link>
</item>
EOR

      assert_parse(make_RDF(<<-EOR), :nothing_raised)
#{make_channel}
#{make_image}
<item rdf:about="http://example.com/hoge.html">
  <title>hoge</title>
  <link>http://example.com/hoge.html</link>
  <description>hogehoge</description>
</item>
EOR

    end

    def test_textinput

      assert_parse(make_RDF(<<-EOR), :missing_attribute, "textinput", "rdf:about")
#{make_channel}
#{make_image}
#{make_item}
<textinput>
</textinput>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "title", "textinput")
#{make_channel}
#{make_image}
#{make_item}
<textinput rdf:about="http://example.com/search.html">
</textinput>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "description", "textinput")
#{make_channel}
#{make_image}
#{make_item}
<textinput rdf:about="http://example.com/search.html">
  <title>hoge</title>
</textinput>
EOR

      assert_too_much_tag("title", "textinput") do
        Parser.parse(make_RDF(<<-EOR))
#{make_channel}
#{make_image}
#{make_item}
<textinput rdf:about="http://example.com/search.html">
  <title>hoge</title>
  <title>hoge</title>
  <description>hogehoge</description>
</textinput>
EOR
      end

      assert_parse(make_RDF(<<-EOR), :missing_tag, "name", "textinput")
#{make_channel}
#{make_image}
#{make_item}
<textinput rdf:about="http://example.com/search.html">
  <title>hoge</title>
  <description>hogehoge</description>
</textinput>
EOR

      assert_parse(make_RDF(<<-EOR), :missing_tag, "link", "textinput")
#{make_channel}
#{make_image}
#{make_item}
<textinput rdf:about="http://example.com/search.html">
  <title>hoge</title>
  <description>hogehoge</description>
  <name>key</name>
</textinput>
EOR

      assert_parse(make_RDF(<<-EOR), :nothing_raised)
#{make_channel}
#{make_image}
#{make_item}
<textinput rdf:about="http://example.com/search.html">
  <title>hoge</title>
  <description>hogehoge</description>
  <name>key</name>
  <link>http://example.com/search.html</link>
</textinput>
EOR

    end

    def test_rss20
      
      assert_parse(make_rss20(<<-EOR), :missing_tag, "channel", "rss")
EOR

      assert_parse(make_rss20(<<-EOR), :nothing_raised)
#{make_channel20("")}
EOR

    end

    def test_cloud20

      attrs = [
        ["domain", CLOUD_DOMAIN],
        ["port", CLOUD_PORT],
        ["path", CLOUD_PATH],
        ["registerProcedure", CLOUD_REGISTER_PROCEDURE],
        ["protocol", CLOUD_PROTOCOL],
      ]
      
      (attrs.size + 1).times do |i|
        missing_attr = attrs[i]
        if missing_attr
          meth = :missing_attribute
          args = ["cloud", missing_attr[0]]
        else
          meth = :nothing_raised
          args = []
        end

        cloud_attrs = []
        attrs.each_with_index do |attr, j|
          unless i == j
            cloud_attrs << %Q[#{attr[0]}="#{attr[1]}"]
          end
        end

        assert_parse(make_rss20(<<-EOR), meth, *args)
#{make_channel20(%Q[<cloud #{cloud_attrs.join("\n")}/>])}
EOR

      end

    end

    def test_source20

        assert_parse(make_rss20(<<-EOR), :missing_attribute, "source", "url")
#{make_channel20(make_item20(%Q[<source>Example</source>]))}
EOR

        assert_parse(make_rss20(<<-EOR), :nothing_raised)
#{make_channel20(make_item20(%Q[<source url="http://example.com/" />]))}
EOR

        assert_parse(make_rss20(<<-EOR), :nothing_raised)
#{make_channel20(make_item20(%Q[<source url="http://example.com/">Example</source>]))}
EOR
    end

    def test_enclosure20

      attrs = [
        ["url", ENCLOSURE_URL],
        ["length", ENCLOSURE_LENGTH],
        ["type", ENCLOSURE_TYPE],
      ]
      
      (attrs.size + 1).times do |i|
        missing_attr = attrs[i]
        if missing_attr
          meth = :missing_attribute
          args = ["enclosure", missing_attr[0]]
        else
          meth = :nothing_raised
          args = []
        end

        enclosure_attrs = []
        attrs.each_with_index do |attr, j|
          unless i == j
            enclosure_attrs << %Q[#{attr[0]}="#{attr[1]}"]
          end
        end

        assert_parse(make_rss20(<<-EOR), meth, *args)
#{make_channel20(%Q[
#{make_item20(%Q[
<enclosure
  #{enclosure_attrs.join("\n")} />
    ])}
  ])}
EOR

      end

    end

    def test_category20
      values = [nil, CATEGORY_DOMAIN]
      
      values.each do |value|
        domain = ""
        domain << %Q[domain="#{value}"] if value

        ["", "Example Text"].each do |text|
          rss_src = make_rss20(<<-EOR)
#{make_channel20(%Q[
#{make_item20(%Q[
<category #{domain}>#{text}</category>
    ])}
  ])}
EOR
          assert_parse(rss_src, :nothing_raised)

          rss = RSS::Parser.parse(rss_src)
          category = rss.items.last.categories.first
          assert_equal(value, category.domain)
          assert_equal(text, category.content)
        end
      end
    end

    def test_ignore

      rss = make_RDF(<<-EOR)
#{make_channel}
#{make_item}
<a/>
EOR

      assert_parse(rss, :nothing_raised)

      assert_not_excepted_tag("a", "RDF") do
        Parser.parse(rss, true, false)
      end

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

