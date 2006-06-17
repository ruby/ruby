require "cgi"

require "rss-testcase"

require "rss/1.0"
require "rss/2.0"
require "rss/taxonomy"

module RSS
  class TestTaxonomy < TestCase
    
    def setup
      @prefix = "taxo"
      @uri = "http://purl.org/rss/1.0/modules/taxonomy/"
      @dc_prefix = "dc"
      @dc_uri = "http://purl.org/dc/elements/1.1/"

      @ns = {
        @prefix => @uri,
        @dc_prefix => @dc_uri,
      }
      
      @parents = %w(channel item)
      
      @topics_lis = [
        "http://meerkat.oreillynet.com/?c=cat23",
        "http://meerkat.oreillynet.com/?c=47",
        "http://dmoz.org/Computers/Data_Formats/Markup_Languages/XML/",
      ]

      @topics_node = "<#{@prefix}:topics>\n"
      @topics_node << "  <rdf:Bag>\n"
      @topics_lis.each do |value|
        resource = CGI.escapeHTML(value)
        @topics_node << "    <rdf:li resource=\"#{resource}\"/>\n"
      end
      @topics_node << "  </rdf:Bag>\n"
      @topics_node << "</#{@prefix}:topics>"

      @topic_topics_lis = \
      [
       "http://meerkat.oreillynet.com/?c=cat23",
       "http://dmoz.org/Computers/Data_Formats/Markup_Languages/SGML/",
       "http://dmoz.org/Computers/Programming/Internet/",
      ]

      @topic_contents = \
      [
       {
         :link => "http://meerkat.oreillynet.com/?c=cat23",
         :title => "Data: XML",
         :description => "A Meerkat channel",
       },
       {
         :link => "http://dmoz.org/Computers/Data_Formats/Markup_Languages/XML/",
         :title => "XML",
         :subject => "XML",
         :description => "DMOZ category",
         :topics => @topic_topics_lis,
       }
      ]

      @topic_nodes = @topic_contents.collect do |info|
        link = info[:link]
        rv = "<#{@prefix}:topic rdf:about=\"#{link}\">\n"
        info.each do |name, value|
          case name
          when :topics
            rv << "<#{@prefix}:topics>\n"
            rv << "  <rdf:Bag>\n"
            value.each do |li|
              resource = CGI.escapeHTML(li)
              rv << "    <rdf:li resource=\"#{resource}\"/>\n"
            end
            rv << "  </rdf:Bag>\n"
            rv << "</#{@prefix}:topics>"
          else
            prefix = (name == :link ? @prefix : @dc_prefix)
            rv << "  <#{prefix}:#{name}>#{value}</#{prefix}:#{name}>\n"
          end
        end
        rv << "</#{@prefix}:topic>"
      end.join("\n")
      
      @rss_source = make_RDF(<<-EOR, @ns)
#{make_channel(@topics_node)}
#{make_image()}
#{make_item(@topics_node)}
#{make_textinput()}
#{@topic_nodes}
EOR

      @rss = Parser.parse(@rss_source)
    end

    def test_parser
      assert_nothing_raised do
        Parser.parse(@rss_source)
      end
      
      assert_too_much_tag("topics", "channel") do
        Parser.parse(make_RDF(<<-EOR, @ns))
#{make_channel(@topics_node * 2)}
#{make_item()}
EOR
      end

      assert_too_much_tag("topics", "item") do
        Parser.parse(make_RDF(<<-EOR, @ns))
#{make_channel()}
#{make_item(@topics_node * 2)}
EOR
      end
    end
  
    def test_accessor
      topics = @rss.channel.taxo_topics
      assert_equal(@topics_lis.sort,
                   topics.Bag.lis.collect {|li| li.resource}.sort)

      assert_equal(@rss.taxo_topics.first, @rss.taxo_topic)

      @topic_contents.each_with_index do |info, i|
        topic = @rss.taxo_topics[i]
        info.each do |name, value|
          case name
          when :link
            assert_equal(value, topic.about)
            assert_equal(value, topic.taxo_link)
          when :topics
            assert_equal(value.sort,
                         topic.taxo_topics.Bag.lis.collect {|li| li.resource}.sort)
          else
            assert_equal(value, topic.__send__("dc_#{name}"))
          end
        end
      end
    end
    
    def test_to_s
      @parents.each do |parent|
        meth = "taxo_topics_element"
        assert_equal(@topics_node, @rss.__send__(parent).__send__(meth))
      end
    end
  end
end

