require "rexml/document"

require "rss-testcase"

require "rss/1.0"

module RSS
  class TestCore < TestCase
    
    def setup
      
      @rdf_prefix = "rdf"
      @rdf_uri = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
      @uri = "http://purl.org/rss/1.0/"
      
    end
    
    def test_RDF
      
      version = "1.0"
      encoding = "UTF-8"
      standalone = false
      
      rdf = RDF.new(version, encoding, standalone)
      
      doc = REXML::Document.new(rdf.to_s(false))
      
      xmldecl = doc.xml_decl
      
      %w(version encoding).each do |x|
        assert_equal(instance_eval(x), xmldecl.send(x))
      end
      assert_equal(standalone, !xmldecl.standalone.nil?)
      
      assert_equal(@rdf_uri, doc.root.namespace)
      
    end
    
    def test_not_displayed_xml_stylesheets
      rdf = RDF.new()
      plain_rdf = rdf.to_s
      3.times do
        rdf.xml_stylesheets.push(XMLStyleSheet.new)
        assert_equal(plain_rdf, rdf.to_s)
      end
    end
    
    def test_xml_stylesheets
      [
        [{:href => "a.xsl", :type => "text/xsl"}],
        [
          {:href => "a.xsl", :type => "text/xsl"},
          {:href => "a.css", :type => "text/css"},
        ],
      ].each do |attrs_ary|
        assert_xml_stylesheet_pis(attrs_ary)
      end
    end
    
    def test_channel
      about = "http://hoge.com"
      title = "fugafuga"
      link = "http://hoge.com"
      description = "fugafugafugafuga"
      resource = "http://hoge.com/hoge.png"
      image = RDF::Channel::Image.new(resource)
      items = RDF::Channel::Items.new
      textinput = RDF::Channel::Textinput.new(resource)
      
      channel = RDF::Channel.new(about)
      %w(title link description image items textinput).each do |x|
        channel.send("#{x}=", instance_eval(x))
      end
      
      doc = REXML::Document.new(make_RDF(channel.to_s))
      c = doc.root.elements[1]
      
      assert_equal(about, c.attributes["about"])
      %w(title link description image textinput).each do |x|
        elem = c.elements[x]
        assert_equal(x, elem.name)
        assert_equal(@uri, elem.namespace)
        if x == "image" or x == "textinput"
          excepted = resource
          res = elem.attributes.get_attribute("resource")
          assert_equal(@rdf_uri, res.namespace)
          value = res.value
        else
          excepted = instance_eval(x)
          value = elem.text
        end
        assert_equal(excepted, value)
      end
      assert_equal(@uri, c.elements["items"].namespace)
      assert_equal("items", c.elements["items"].name)
      
    end
    
    def test_channel_image
      
      resource = "http://hoge.com/hoge.png"
      image = RDF::Channel::Image.new(resource)
      
      doc = REXML::Document.new(make_RDF(image.to_s))
      i = doc.root.elements[1]
      
      assert_equal("image", i.name)
      assert_equal(@uri, i.namespace)
      
      res = i.attributes.get_attribute("resource")
      
      assert_equal(@rdf_uri, res.namespace)
      assert_equal(resource, res.value)
      
    end
    
    def test_channel_textinput
      
      resource = "http://hoge.com/hoge.png"
      textinput = RDF::Channel::Textinput.new(resource)
      
      doc = REXML::Document.new(make_RDF(textinput.to_s))
      t = doc.root.elements[1]
      
      assert_equal("textinput", t.name)
      assert_equal(@uri, t.namespace)
      
      res = t.attributes.get_attribute("resource")
      
      assert_equal(@rdf_uri, res.namespace)
      assert_equal(resource, res.value)
      
    end
    
    def test_items
      
      items = RDF::Channel::Items.new
      
      doc = REXML::Document.new(make_RDF(items.to_s))
      i = doc.root.elements[1]
      
      assert_equal("items", i.name)
      assert_equal(@uri, i.namespace)
      
      assert_equal(1, i.elements.size)
      assert_equal("Seq", i.elements[1].name)
      assert_equal(@rdf_uri, i.elements[1].namespace)
      
    end
    
    def test_seq
      
      seq = RDF::Seq.new
      
      doc = REXML::Document.new(make_RDF(seq.to_s))
      s = doc.root.elements[1]
      
      assert_equal("Seq", s.name)
      assert_equal(@rdf_uri, s.namespace)
      
    end
    
    def test_li
      
      resource = "http://hoge.com/"
      li = RDF::Li.new(resource)
      
      doc = REXML::Document.new(make_RDF(li.to_s))
      l = doc.root.elements[1]
      
      assert_equal("li", l.name)
      assert_equal(@rdf_uri, l.namespace(l.prefix))
      
      res = l.attributes.get_attribute("resource")
      
      assert_equal('', res.instance_eval("@prefix"))
      assert_equal(resource, res.value)
      
    end
    
    def test_image
      
      about = "http://hoge.com"
      title = "fugafuga"
      url = "http://hoge.com/hoge"
      link = "http://hoge.com/fuga"
      
      image = RDF::Image.new(about)
      %w(title url link).each do |x|
        image.send("#{x}=", instance_eval(x))
      end
      
      doc = REXML::Document.new(make_RDF(image.to_s))
      i = doc.root.elements[1]
      
      assert_equal(about, i.attributes["about"])
      %w(title url link).each do |x|
        elem = i.elements[x]
        assert_equal(x, elem.name)
        assert_equal(@uri, elem.namespace)
        assert_equal(instance_eval(x), elem.text)
      end
      
    end
    
    def test_item
      
      about = "http://hoge.com"
      title = "fugafuga"
      link = "http://hoge.com/fuga"
      description = "hogehogehoge"
      
      item = RDF::Item.new(about)
      %w(title link description).each do |x|
        item.send("#{x}=", instance_eval(x))
      end
      
      doc = REXML::Document.new(make_RDF(item.to_s))
      i = doc.root.elements[1]
      
      assert_equal(about, i.attributes["about"])
      %w(title link description).each do |x|
        elem = i.elements[x]
        assert_equal(x, elem.name)
        assert_equal(@uri, elem.namespace)
        assert_equal(instance_eval(x), elem.text)
      end
      
    end
    
    def test_textinput
      
      about = "http://hoge.com"
      title = "fugafuga"
      link = "http://hoge.com/fuga"
      name = "foo"
      description = "hogehogehoge"
      
      textinput = RDF::Textinput.new(about)
      %w(title link name description).each do |x|
        textinput.send("#{x}=", instance_eval(x))
      end
      
      doc = REXML::Document.new(make_RDF(textinput.to_s))
      t = doc.root.elements[1]
      
      assert_equal(about, t.attributes["about"])
      %w(title link name description).each do |x|
        elem = t.elements[x]
        assert_equal(x, elem.name)
        assert_equal(@uri, elem.namespace)
        assert_equal(instance_eval(x), elem.text)
      end
      
    end

    def test_indent_size
      assert_equal(0, RDF.indent_size)
      assert_equal(1, RDF::Channel.indent_size)
      assert_equal(2, RDF::Channel::Image.indent_size)
      assert_equal(2, RDF::Channel::Textinput.indent_size)
      assert_equal(2, RDF::Channel::Items.indent_size)
      assert_equal(1, RDF::Image.indent_size)
      assert_equal(1, RDF::Item.indent_size)
      assert_equal(1, RDF::Textinput.indent_size)
    end
    
  end
end
