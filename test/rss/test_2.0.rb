require "rexml/document"

require "rss-testcase"

require "rss/2.0"

module RSS
  class TestRSS20Core < TestCase

    def setup
      @rss_version = "2.0"
    end
    
    def test_Rss
      version = "1.0"
      encoding = "UTF-8"
      standalone = false
      
      rss = Rss.new(@rss_version, version, encoding, standalone)
      
      doc = REXML::Document.new(rss.to_s(false))
      
      xmldecl = doc.xml_decl
      
      %w(version encoding).each do |x|
        assert_equal(instance_eval(x), xmldecl.__send__(x))
      end
      assert_equal(standalone, !xmldecl.standalone.nil?)
      
      assert_equal("", doc.root.namespace)
      assert_equal(@rss_version, doc.root.attributes["version"])
    end
    
    def test_not_displayed_xml_stylesheets
      rss = Rss.new(@rss_version)
      plain_rss = rss.to_s
      3.times do
        rss.xml_stylesheets.push(XMLStyleSheet.new)
        assert_equal(plain_rss, rss.to_s)
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
        assert_xml_stylesheet_pis(attrs_ary, Rss.new(@rss_version))
      end
    end

    def test_channel
      title = "fugafuga"
      link = "http://hoge.com"
      description = "fugafugafugafuga"
      
      language = "en-us"
      copyright = "Copyright 2002, Spartanburg Herald-Journal"
      managingEditor = "geo@herald.com (George Matesky)"
      webMaster = "betty@herald.com (Betty Guernsey)"
      pubDate = Time.parse("Sat, 07 Sep 2002 00:00:01 GMT")
      lastBuildDate = Time.parse("Sat, 07 Sep 2002 09:42:31 GMT")
      categories = [
        {
          :content => "Newspapers",
        },
        {
          :domain => "Syndic8",
          :content => "1765",
        }
      ]
      generator = "MightyInHouse Content System v2.3"
      docs = "http://blogs.law.harvard.edu/tech/rss"

      ttl = 60

      rating = 6

      channel = Rss::Channel.new
      
      elems = %w(title link description language copyright
                 managingEditor webMaster pubDate lastBuildDate
                 generator docs ttl rating)
      elems.each do |x|
        channel.__send__("#{x}=", instance_eval(x))
      end
      categories.each do |cat|
        channel.categories << Rss::Channel::Category.new(cat[:domain],
                                                         cat[:content])
      end
      
      doc = REXML::Document.new(make_rss20(channel.to_s))
      c = doc.root.elements[1]
      
      elems.each do |x|
        elem = c.elements[x]
        assert_equal(x, elem.name)
        assert_equal("", elem.namespace)
        expected = instance_eval(x)
        case x
        when "pubDate", "lastBuildDate"
          assert_equal(expected, Time.parse(elem.text))
        when "ttl", "rating"
          assert_equal(expected, elem.text.to_i)
        else
          assert_equal(expected, elem.text)
        end
      end
      categories.each_with_index do |cat, i|
        cat = cat.dup
        cat[:domain] ||= nil
        category = c.elements["category[#{i+1}]"]
        actual = {
          :domain => category.attributes["domain"],
          :content => category.text,
        }
        assert_equal(cat, actual)
      end
    end

    def test_channel_cloud
      cloud_params = {
        :domain => "rpc.sys.com",
        :port => 80,
        :path => "/RPC2",
        :registerProcedure => "myCloud.rssPleaseNotify",
        :protocol => "xml-rpc",
      }
      cloud = Rss::Channel::Cloud.new(cloud_params[:domain],
                                      cloud_params[:port],
                                      cloud_params[:path],
                                      cloud_params[:registerProcedure],
                                      cloud_params[:protocol])
                                      
      doc = REXML::Document.new(cloud.to_s)
      cloud_elem = doc.root
      
      actual = {}
      cloud_elem.attributes.each do |name, value|
        value = value.to_i if name == "port"
        actual[name.to_sym] = value
      end
      assert_equal(cloud_params, actual)
    end

    def test_channel_image
      image_params = {
        :url => "http://hoge.com/hoge.png",
        :title => "fugafuga",
        :link => "http://hoge.com",
        :width => 144,
        :height => 400,
        :description => "an image",
      }
      image = Rss::Channel::Image.new(image_params[:url],
                                      image_params[:title],
                                      image_params[:link],
                                      image_params[:width],
                                      image_params[:height],
                                      image_params[:description])

      doc = REXML::Document.new(image.to_s)
      image_elem = doc.root
      
      image_params.each do |name, value|
        actual = image_elem.elements[name.to_s].text
        actual = actual.to_i if [:width, :height].include?(name)
        assert_equal(value, actual)
      end
    end
    
    def test_channel_textInput
      textInput_params = {
        :title => "fugafuga",
        :description => "text hoge fuga",
        :name => "hoge",
        :link => "http://hoge.com",
      }
      textInput = Rss::Channel::TextInput.new(textInput_params[:title],
                                              textInput_params[:description],
                                              textInput_params[:name],
                                              textInput_params[:link])

      doc = REXML::Document.new(textInput.to_s)
      input_elem = doc.root
      
      textInput_params.each do |name, value|
        actual = input_elem.elements[name.to_s].text
        assert_equal(value, actual)
      end
    end
    
    def test_channel_skip_days
      skipDays_values = [
        "Sunday",
        "Monday",
      ]
      skipDays = Rss::Channel::SkipDays.new
      skipDays_values.each do |value|
        skipDays.days << Rss::Channel::SkipDays::Day.new(value)
      end
      
      doc = REXML::Document.new(skipDays.to_s)
      days_elem = doc.root
      
      skipDays_values.each_with_index do |value, i|
        assert_equal(value, days_elem.elements[i + 1].text)
      end
    end
    
    def test_channel_skip_hours
      skipHours_values = [
        0,
        13,
      ]
      skipHours = Rss::Channel::SkipHours.new
      skipHours_values.each do |value|
        skipHours.hours << Rss::Channel::SkipHours::Hour.new(value)
      end

      doc = REXML::Document.new(skipHours.to_s)
      hours_elem = doc.root
      
      skipHours_values.each_with_index do |value, i|
        assert_equal(value, hours_elem.elements[i + 1].text.to_i)
      end
    end

    def test_item
      title = "fugafuga"
      link = "http://hoge.com/"
      description = "text hoge fuga"
      author = "oprah@oxygen.net"
      categories = [
        {
          :content => "Newspapers",
        },
        {
          :domain => "Syndic8",
          :content => "1765",
        }
      ]
      comments = "http://www.myblog.org/cgi-local/mt/mt-comments.cgi?entry_id=290"
      pubDate = Time.parse("Sat, 07 Sep 2002 00:00:01 GMT")

      channel = Rss::Channel.new
      item = Rss::Channel::Item.new
      channel.items << item
      
      elems = %w(title link description author comments pubDate)
      elems.each do |x|
        item.__send__("#{x}=", instance_eval(x))
      end
      categories.each do |cat|
        item.categories << Rss::Channel::Category.new(cat[:domain],
                                                      cat[:content])
      end
      
      doc = REXML::Document.new(channel.to_s)
      channel_elem = doc.root

      item_elem = channel_elem.elements["item[1]"]
      elems.each do |x|
        elem = item_elem.elements[x]
        assert_equal(x, elem.name)
        assert_equal("", elem.namespace)
        expected = instance_eval(x)
        case x
        when "pubDate"
          assert_equal(expected, Time.parse(elem.text))
        else
          assert_equal(expected, elem.text)
        end
      end
      categories.each_with_index do |cat, i|
        cat = cat.dup
        cat[:domain] ||= nil
        category = item_elem.elements["category[#{i+1}]"]
        actual = {
          :domain => category.attributes["domain"],
          :content => category.text,
        }
        assert_equal(cat, actual)
      end
    end

    def test_item_enclosure
      enclosure_params = {
        :url => "http://www.scripting.com/mp3s/weatherReportSuite.mp3",
        :length => 12216320,
        :type => "audio/mpeg",
      }

      enclosure = Rss::Channel::Item::Enclosure.new(enclosure_params[:url],
                                                    enclosure_params[:length],
                                                    enclosure_params[:type])

      doc = REXML::Document.new(enclosure.to_s)
      enclosure_elem = doc.root

      actual = {}
      enclosure_elem.attributes.each do |name, value|
        if name == "length"
          enclosure_params[name.to_sym] = value.to_i
          value = value.to_i
        end
        actual[name.to_sym] = value
      end
      assert_equal(enclosure_params, actual)
    end
    
    def test_item_guid
      test_params = [
        {
          :content => "http://some.server.com/weblogItem3207",
        },
        {
          :isPermaLink => "true",
          :content => "http://inessential.com/2002/09/01.php#a2",
        },
      ]

      test_params.each do |guid_params|
        guid = Rss::Channel::Item::Guid.new(guid_params[:isPermaLink],
                                            guid_params[:content])

        doc = REXML::Document.new(guid.to_s)
        guid_elem = doc.root
      
        actual = {}
        actual[:content] = guid_elem.text if guid_elem.text
        guid_elem.attributes.each do |name, value|
          actual[name.to_sym] = value
        end
        assert_equal(guid_params, actual)
      end
    end
    
    def test_item_source
      source_params = {
        :url => "http://www.tomalak.org/links2.xml",
        :content => "Tomalak's Realm",
      }

      source = Rss::Channel::Item::Source.new(source_params[:url],
                                              source_params[:content])

      doc = REXML::Document.new(source.to_s)
      source_elem = doc.root
      
      actual = {}
      actual[:content] = source_elem.text
      source_elem.attributes.each do |name, value|
        actual[name.to_sym] = value
      end
      assert_equal(source_params, actual)
    end
    
    def test_indent_size
      assert_equal(0, Rss.indent_size)
      assert_equal(1, Rss::Channel.indent_size)
      assert_equal(2, Rss::Channel::SkipDays.indent_size)
      assert_equal(3, Rss::Channel::SkipDays::Day.indent_size)
      assert_equal(2, Rss::Channel::SkipHours.indent_size)
      assert_equal(3, Rss::Channel::SkipHours::Hour.indent_size)
      assert_equal(2, Rss::Channel::Image.indent_size)
      assert_equal(2, Rss::Channel::Cloud.indent_size)
      assert_equal(2, Rss::Channel::Item.indent_size)
      assert_equal(3, Rss::Channel::Item::Source.indent_size)
      assert_equal(3, Rss::Channel::Item::Enclosure.indent_size)
      assert_equal(3, Rss::Channel::Item::Category.indent_size)
      assert_equal(3, Rss::Channel::Item::Guid.indent_size)
      assert_equal(2, Rss::Channel::TextInput.indent_size)
    end
  end
end
