require "cgi"
require "rexml/document"

require "rss-testcase"

require "rss/1.0"
require "rss/dublincore"

module RSS
  class TestDublinCore < TestCase

    def setup
      @prefix = "dc"
      @uri = "http://purl.org/dc/elements/1.1/"
      
      @parents = %w(channel image item textinput)
      
      t = Time.iso8601("2000-01-01T12:00:05+00:00")
      class << t
        alias_method(:to_s, :iso8601)
      end
      
      @elems = {
        :title => "hoge",
        :description =>
          " XML is placing increasingly heavy loads on
          the existing technical infrastructure of the Internet.",
        :creator => "Rael Dornfest (mailto:rael@oreilly.com)",
        :subject => "XML",
        :publisher => "The O'Reilly Network",
        :contributor => "hogehoge",
        :type => "fugafuga",
        :format => "hohoho",
        :identifier => "fufufu",
        :source => "barbar",
        :language => "ja",
        :relation => "cococo",
        :rights => "Copyright (c) 2000 O'Reilly &amp; Associates, Inc.",
        :date => t,
      }

      @dc_nodes = @elems.collect do |name, value|
        "<#{@prefix}:#{name}>#{value}</#{@prefix}:#{name}>"
      end.join("\n")

      @rss_source = make_RDF(<<-EOR, {@prefix =>  @uri})
#{make_channel(@dc_nodes)}
#{make_image(@dc_nodes)}
#{make_item(@dc_nodes)}
#{make_textinput(@dc_nodes)}
EOR

      @rss = Parser.parse(@rss_source)
    end
  
    def test_parser

      assert_nothing_raised do
        Parser.parse(@rss_source)
      end
    
      @elems.each do |tag, value|
        assert_too_much_tag(tag.to_s, "channel") do
          Parser.parse(make_RDF(<<-EOR, {@prefix => @uri}))
#{make_channel(("<" + @prefix + ":" + tag.to_s + ">" +
  value.to_s +
  "</" + @prefix + ":" + tag.to_s + ">") * 2)}
#{make_item}
EOR
        end
      end

    end
  
    def test_accessor
    
      new_value = "hoge"

      @elems.each do |name, value|
        @parents.each do |parent|
          parsed_value = @rss.send(parent).send("dc_#{name}")
          if parsed_value.kind_of?(String)
            parsed_value = CGI.escapeHTML(parsed_value)
          end
          assert_equal(value, parsed_value)
          if name == :date
            t = Time.iso8601("2003-01-01T02:30:23+09:00")
            class << t
              alias_method(:to_s, :iso8601)
            end
            @rss.send(parent).send("dc_#{name}=", t.iso8601)
            assert_equal(t, @rss.send(parent).send("dc_#{name}"))
          else
            @rss.send(parent).send("dc_#{name}=", new_value)
            assert_equal(new_value, @rss.send(parent).send("dc_#{name}"))
          end
        end
      end

    end

    def test_to_s
      
      @elems.each do |name, value|
        excepted = "<#{@prefix}:#{name}>#{value}</#{@prefix}:#{name}>"
        @parents.each do |parent|
          assert_equal(excepted, @rss.send(parent).send("dc_#{name}_element"))
        end
      end
      
      REXML::Document.new(@rss_source).root.each_element do |parent|
        if @parents.include?(parent.name)
          parent.each_element do |elem|
            if elem.namespace == @uri
              assert_equal(CGI.escapeHTML(elem.text), @elems[elem.name.intern].to_s)
            end
          end
        end
      end
      
    end

  end
end
