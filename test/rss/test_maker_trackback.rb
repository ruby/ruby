require "rss-testcase"

require "rss/maker"

module RSS
  class TestMakerTrackBack < TestCase

    def setup
      @uri = "http://madskills.com/public/xml/rss/module/trackback/"
      
      @elements = {
        :ping => "http://bar.com/tb.cgi?tb_id=rssplustrackback",
        :about => "http://foo.com/trackback/tb.cgi?tb_id=20020923",
      }
    end

    def test_rss10
      rss = RSS::Maker.make("1.0", ["trackback"]) do |maker|
        setup_dummy_channel(maker)

        setup_dummy_item(maker)
        item = maker.items.last
        @elements.each do |name, value|
          item.__send__("#{accessor_name(name)}=", value)
        end
      end
      assert_trackback(@elements, rss.items.last)
    end

    private
    def accessor_name(name)
      "trackback_#{name}"
    end
  end
end
