# -*- tab-width: 2 -*- vim: ts=2

require "rss-testcase"

require "rss/1.0"

module RSS
	class TestParser < TestCase
		
		def setup
			@_default_parser = Parser.default_parser
		end
		
		def teardown
			Parser.default_parser = @_default_parser
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

			assert_not_excepted_tag("image", "RDF") do
				Parser.parse(make_RDF(<<-EOR))
#{make_channel}
#{make_item}
#{make_image}
#{make_textinput}
EOR
			end

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

		def test_channel

			assert_parse(make_RDF(<<-EOR), :missing_attribute, "channel", "about")
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

			assert_parse(make_RDF(<<-EOR), :missing_attribute, "image", "resource")
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

			assert_parse(make_RDF(<<-EOR), :missing_attribute, "textinput", "resource")
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

	  def test_image

			assert_parse(make_RDF(<<-EOR), :missing_attribute, "image", "about")
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

			rss = make_RDF(<<-EOR)
#{make_channel}
<image rdf:about="http://example.com/hoge.png">
  <title>hoge</title>
  <link>http://example.com/</link>
  <url>http://example.com/hoge.png</url>
</image>
EOR

			assert_missing_tag("url", "image") do
				Parser.parse(rss)
			end

			assert_missing_tag("item", "RDF") do
				Parser.parse(rss, false).validate
			end

			assert_parse(make_RDF(<<-EOR), :missing_tag, "item", "RDF")
#{make_channel}
<image rdf:about="http://example.com/hoge.png">
  <title>hoge</title>
  <url>http://example.com/hoge.png</url>
  <link>http://example.com/</link>
</image>
EOR

	  end

		def test_item

			assert_parse(make_RDF(<<-EOR), :missing_attribute, "item", "about")
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

			assert_parse(make_RDF(<<-EOR), :missing_attribute, "textinput", "about")
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
			assert_nothing_raised() do
				Parser.default_parser = RSS::AVAILABLE_PARSERS.first
			end

			assert_raise(RSS::NotValidXMLParser) do
				Parser.default_parser = RSS::Parser
			end
		end

	end
end

