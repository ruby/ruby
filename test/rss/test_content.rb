require "cgi"
require "rexml/document"

require "rss-testcase"

require "rss/1.0"
require "rss/content"

module RSS
  class TestContent < TestCase
    
    def setup
      @prefix = "content"
      @uri = "http://purl.org/rss/1.0/modules/content/"
      
      @parents = %w(item)
      
      @elems = {
        :encoded => "<em>ATTENTION</em>",
      }
      
      @content_nodes = @elems.collect do |name, value|
        "<#{@prefix}:#{name}>#{CGI.escapeHTML(value.to_s)}</#{@prefix}:#{name}>"
      end.join("\n")
      
      @rss_source = make_RDF(<<-EOR, {@prefix =>  @uri})
#{make_channel()}
#{make_image()}
#{make_item(@content_nodes)}
#{make_textinput()}
EOR

      @rss = Parser.parse(@rss_source)
    end
  
    def test_parser

      assert_nothing_raised do
        Parser.parse(@rss_source)
      end
    
      @elems.each do |tag, value|
        assert_too_much_tag(tag.to_s, "item") do
          Parser.parse(make_RDF(<<-EOR, {@prefix => @uri}))
#{make_channel()}
#{make_item(("<" + @prefix + ":" + tag.to_s + ">" +
  CGI.escapeHTML(value.to_s) +
  "</" + @prefix + ":" + tag.to_s + ">") * 2)}
EOR
        end
      end

    end
  
    def test_accessor
    
      new_value = {
        :encoded => "<![CDATA[<it>hoge</it>]]>",
      }

      @elems.each do |name, value|
        @parents.each do |parent|
          meth = "#{RSS::CONTENT_PREFIX}_#{name}"
          assert_equal(value, @rss.send(parent).send(meth))
          @rss.send(parent).send("#{meth}=", new_value[name].to_s)
          assert_equal(new_value[name], @rss.send(parent).send(meth))
        end
      end

    end
    
    def test_to_s
      
      @elems.each do |name, value|
        excepted = "<#{@prefix}:#{name}>#{CGI.escapeHTML(value)}</#{@prefix}:#{name}>"
        @parents.each do |parent|
          meth = "#{RSS::CONTENT_PREFIX}_#{name}_element"
          assert_equal(excepted, @rss.send(parent).send(meth))
        end
      end

      REXML::Document.new(@rss_source).root.each_element do |parent|
        if @parents.include?(parent.name)
          parent.each_element do |elem|
            if elem.namespace == @uri
              assert_equal(elem.text, @elems[elem.name.intern].to_s)
            end
          end
        end
      end
      
    end
  
  end
end
