require "rss-testcase"

require "rss/maker"

module RSS
  class TestSetupMaker10 < TestCase

    def setup
      t = Time.iso8601("2000-01-01T12:00:05+00:00")
      class << t
        alias_method(:to_s, :iso8601)
      end
      
      @dc_elems = {
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

      @sy_elems = {
        :updatePeriod => "hourly",
        :updateFrequency => 2,
        :updateBase => t,
      }

      @content_elems = {
        :encoded => "<em>ATTENTION</em>",
      }
      
      @trackback_elems = {
        :ping => "http://bar.com/tb.cgi?tb_id=rssplustrackback",
        :about => [
          "http://foo.com/trackback/tb.cgi?tb_id=20020923",
          "http://foo.com/trackback/tb.cgi?tb_id=20021010",
        ],
      }
    end
    
    def test_setup_maker_channel
      about = "http://hoge.com"
      title = "fugafuga"
      link = "http://hoge.com"
      description = "fugafugafugafuga"

      rss = RSS::Maker.make("1.0") do |maker|
        maker.channel.about = about
        maker.channel.title = title
        maker.channel.link = link
        maker.channel.description = description
        
        @dc_elems.each do |var, value|
          maker.channel.__send__("dc_#{var}=", value)
        end

        @sy_elems.each do |var, value|
          maker.channel.__send__("sy_#{var}=", value)
        end
      end

      new_rss = RSS::Maker.make("1.0") do |maker|
        rss.channel.setup_maker(maker)
      end
      channel = new_rss.channel
      
      assert_equal(about, channel.about)
      assert_equal(title, channel.title)
      assert_equal(link, channel.link)
      assert_equal(description, channel.description)
      assert_equal(true, channel.items.Seq.lis.empty?)
      assert_nil(channel.image)
      assert_nil(channel.textinput)

      @dc_elems.each do |var, value|
        assert_equal(channel.__send__("dc_#{var}"), value)
      end
      
      @sy_elems.each do |var, value|
        assert_equal(channel.__send__("sy_#{var}"), value)
      end
      
    end

    def test_setup_maker_image
      title = "fugafuga"
      link = "http://hoge.com"
      url = "http://hoge.com/hoge.png"
      
      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        maker.channel.link = link
        
        maker.image.title = title
        maker.image.url = url

        @dc_elems.each do |var, value|
          maker.image.__send__("dc_#{var}=", value)
        end
      end
      
      new_rss = RSS::Maker.make("1.0") do |maker|
        rss.channel.setup_maker(maker)
        rss.image.setup_maker(maker)
      end
      
      image = new_rss.image
      assert_equal(url, image.about)
      assert_equal(url, new_rss.channel.image.resource)
      assert_equal(title, image.title)
      assert_equal(link, image.link)
      assert_equal(url, image.url)

      @dc_elems.each do |var, value|
        assert_equal(image.__send__("dc_#{var}"), value)
      end
    end
    
    def test_setup_maker_textinput
      title = "fugafuga"
      description = "text hoge fuga"
      name = "hoge"
      link = "http://hoge.com"

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        
        maker.textinput.link = link
        maker.textinput.title = title
        maker.textinput.description = description
        maker.textinput.name = name

        @dc_elems.each do |var, value|
          maker.textinput.__send__("dc_#{var}=", value)
        end
      end
      
      new_rss = RSS::Maker.make("1.0") do |maker|
        rss.channel.setup_maker(maker)
        rss.textinput.setup_maker(maker)
      end
      
      textinput = new_rss.textinput
      assert_equal(link, textinput.about)
      assert_equal(link, new_rss.channel.textinput.resource)
      assert_equal(title, textinput.title)
      assert_equal(name, textinput.name)
      assert_equal(description, textinput.description)
      assert_equal(link, textinput.link)

      @dc_elems.each do |var, value|
        assert_equal(textinput.__send__("dc_#{var}"), value)
      end
    end

    def test_setup_maker_items
      title = "TITLE"
      link = "http://hoge.com/"
      description = "text hoge fuga"

      item_size = 5
      
      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        
        item_size.times do |i|
          item = maker.items.new_item
          item.title = "#{title}#{i}"
          item.link = "#{link}#{i}"
          item.description = "#{description}#{i}"

          @dc_elems.each do |var, value|
            item.__send__("dc_#{var}=", value)
          end
          
          @content_elems.each do |var, value|
            item.__send__("content_#{var}=", value)
          end

          item.trackback_ping = @trackback_elems[:ping]
          @trackback_elems[:about].each do |value|
            new_about = item.trackback_abouts.new_about
            new_about.value = value
          end
        end
      end
      
      new_rss = RSS::Maker.make("1.0") do |maker|
        rss.channel.setup_maker(maker)

        rss.items.each do |item|
          item.setup_maker(maker)
        end
      end
      
      assert_equal(item_size, new_rss.items.size)
      new_rss.items.each_with_index do |item, i|
        assert_equal("#{link}#{i}", item.about)
        assert_equal("#{title}#{i}", item.title)
        assert_equal("#{link}#{i}", item.link)
        assert_equal("#{description}#{i}", item.description)

        @dc_elems.each do |var, value|
          assert_equal(item.__send__("dc_#{var}"), value)
        end
      
        @content_elems.each do |var, value|
          assert_equal(item.__send__("content_#{var}"), value)
        end
      
        assert_equal(@trackback_elems[:ping], item.trackback_ping)
        assert_equal(@trackback_elems[:about].size, item.trackback_abouts.size)
        item.trackback_abouts.each_with_index do |about, i|
          assert_equal(@trackback_elems[:about][i], about.value)
        end
      end

    end

    def test_setup_maker
      encoding = "EUC-JP"
      standalone = true
      
      href = 'a.xsl'
      type = 'text/xsl'
      title = 'sample'
      media = 'printer'
      charset = 'UTF-8'
      alternate = 'yes'

      rss = RSS::Maker.make("1.0") do |maker|
        maker.encoding = encoding
        maker.standalone = standalone

        xss = maker.xml_stylesheets.new_xml_stylesheet
        xss.href = href
        xss.type = type
        xss.title = title
        xss.media = media
        xss.charset = charset
        xss.alternate = alternate
        
        setup_dummy_channel(maker)
      end
      
      new_rss = RSS::Maker.make("1.0") do |maker|
        rss.setup_maker(maker)
      end
      
      assert_equal("1.0", new_rss.rss_version)
      assert_equal(encoding, new_rss.encoding)
      assert_equal(standalone, new_rss.standalone)

      xss = rss.xml_stylesheets.first
      assert_equal(1, rss.xml_stylesheets.size)
      assert_equal(href, xss.href)
      assert_equal(type, xss.type)
      assert_equal(title, xss.title)
      assert_equal(media, xss.media)
      assert_equal(charset, xss.charset)
      assert_equal(alternate, xss.alternate)
    end
    
  end
end
