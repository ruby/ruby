# -*- tab-width: 2 -*- vim: ts=2

require "test/unit"
require "cgi"
require "rexml/document"

require "rss/1.0"
require "rss/2.0"
require "rss/trackback"
require "common"

class TestTrackBack < Test::Unit::TestCase
	include TestRSSMixin

	def setup
		@prefix = "trackback"
		@uri = "http://madskills.com/public/xml/rss/module/trackback/"
		
		@parents = %w(item)

		@elems = {
			:ping => "http://bar.com/tb.cgi?tb_id=rssplustrackback",
			:about => "http://foo.com/trackback/tb.cgi?tb_id=20020923",
		}

		@content_nodes = @elems.collect do |name, value|
			"<#{@prefix}:#{name} rdf:resource=\"#{CGI.escapeHTML(value.to_s)}\"/>"
		end.join("\n")

		@content_nodes2 = @elems.collect do |name, value|
			"<#{@prefix}:#{name}>#{CGI.escapeHTML(value.to_s)}</#{@prefix}:#{name}>"
		end.join("\n")

		@rss_source = make_RDF(<<-EOR, {@prefix =>  @uri})
#{make_channel()}
#{make_image()}
#{make_item(@content_nodes)}
#{make_textinput()}
EOR

		@rss = Parser.parse(@rss_source)

		@rss2_source = make_Rss2(nil, {@prefix =>  @uri}) do
			make_channel2(nil) do
				make_item2(@content_nodes2)
			end
		end

		@rss2 = Parser.parse(@rss2_source, false)
	end

	def test_parser

		assert_nothing_raised do
			Parser.parse(@rss_source)
		end

		@elems.find_all{|k, v| k == :ping}.each do |tag, value|
			assert_too_much_tag(tag.to_s, "item") do
				Parser.parse(make_RDF(<<-EOR, {@prefix => @uri}))
#{make_channel()}
#{make_item(("<" + @prefix + ":" + tag.to_s + " rdf:resource=\"" +
	CGI.escapeHTML(value.to_s) +
	"\"/>") * 2)}
EOR
			end
		end

		@elems.find_all{|k, v| k == :about}.each do |tag, value|
			assert_missing_tag("trackback:ping", "item") do
				Parser.parse(make_RDF(<<-EOR, {@prefix => @uri}))
#{make_channel()}
#{make_item(("<" + @prefix + ":" + tag.to_s + " rdf:resource=\"" +
	CGI.escapeHTML(value.to_s) +
	"\"/>") * 2)}
EOR
			end

		end

	end
	
	def test_accessor
		
		new_value = {
			:ping => "http://baz.com/trackback/tb.cgi?tb_id=20030808",
			:about => "http://hoge.com/trackback/tb.cgi?tb_id=90030808",
		}

		@elems.each do |name, value|
			@parents.each do |parent|
				accessor = "#{RSS::TRACKBACK_PREFIX}_#{name}"
				target_accessor = "resource"
				target = @rss.send(parent).send(accessor)
				target2 = @rss2.channel.send(parent, -1)
				assert_equal(value, target.send(target_accessor))
				assert_equal(value, target2.send(accessor))
				target.send("#{target_accessor}=", new_value[name].to_s)
				if name == :about
					# abount is zero or more
					target2.send("#{accessor}=", 0, new_value[name].to_s)
				else
					target2.send("#{accessor}=", new_value[name].to_s)
				end
				assert_equal(new_value[name], target.send(target_accessor))
				assert_equal(new_value[name], target2.send(accessor))
			end
		end

	end

	def test_to_s
		
		@elems.each do |name, value|
			excepted = %Q!<#{@prefix}:#{name} rdf:resource="#{CGI.escapeHTML(value)}"/>!
			@parents.each do |parent|
				meth = "#{RSS::TRACKBACK_PREFIX}_#{name}_element"
				meth << "s" if name == :about
				assert_equal(excepted, @rss.send(parent).send(meth))
			end
		end

		REXML::Document.new(@rss_source).root.each_element do |parent|
			if @parents.include?(parent.name)
				parent.each_element do |elem|
					if elem.namespace == @uri
						assert_equal(elem.attributes["resource"], @elems[elem.name.intern])
					end
				end
			end
		end

	end
	
end
