require "rss-testcase"

require "rss/maker"

module RSS
  class TestMakerDublinCore < TestCase

    def setup
      @uri = "http://purl.org/dc/elements/1.1/"
      
      t = Time.iso8601("2000-01-01T12:00:05+00:00")
      class << t
        alias_method(:to_s, :iso8601)
      end
      
      @elements = {
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
    end

    def test_rss10
      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        set_elements(maker.channel)

        setup_dummy_image(maker)
        set_elements(maker.image)

        setup_dummy_item(maker)
        item = maker.items.last
        @elements.each do |name, value|
          item.__send__("#{accessor_name(name)}=", value)
        end

        setup_dummy_textinput(maker)
        set_elements(maker.textinput)
      end
      assert_dublin_core(@elements, rss.channel)
      assert_dublin_core(@elements, rss.image)
      assert_dublin_core(@elements, rss.items.last)
      assert_dublin_core(@elements, rss.textinput)
    end

    private
    def accessor_name(name)
      "dc_#{name}"
    end

    def set_elements(target)
      @elements.each do |name, value|
        target.__send__("#{accessor_name(name)}=", value)
      end
    end

  end
end
