require "rss-testcase"

require "rss/maker"

module RSS
  class TestMakerXMLStyleSheet < TestCase

    def test_rss10
      href = 'a.xsl'
      type = 'text/xsl'
      title = 'sample'
      media = 'printer'
      charset = 'UTF-8'
      alternate = 'yes'

      rss = RSS::Maker.make("1.0") do |maker|
        maker.xml_stylesheets << {
          :href => href,
          :type => type,
          :title => title,
          :media => media,
          :charset => charset,
          :alternate => alternate,
        }
        
        setup_dummy_channel(maker)
      end

      xss = rss.xml_stylesheets.first
      assert_equal(href, xss.href)
      assert_equal(type, xss.type)
      assert_equal(title, xss.title)
      assert_equal(media, xss.media)
      assert_equal(charset, xss.charset)
      assert_equal(alternate, xss.alternate)
    end
    
  end
end
