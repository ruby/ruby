require "rss-testcase"

require "rss/maker"

module RSS
  class TestMaker10 < TestCase

    def test_rdf
      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
      end
      assert_equal("1.0", rss.rss_version)
      
      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        maker.encoding = "EUC-JP"
      end
      assert_equal("1.0", rss.rss_version)
      assert_equal("EUC-JP", rss.encoding)

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        maker.standalone = "yes"
      end
      assert_equal("1.0", rss.rss_version)
      assert_equal("yes", rss.standalone)

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        maker.encoding = "EUC-JP"
        maker.standalone = "yes"
      end
      assert_equal("1.0", rss.rss_version)
      assert_equal("EUC-JP", rss.encoding)
      assert_equal("yes", rss.standalone)
    end

    def test_channel
      about = "http://hoge.com"
      title = "fugafuga"
      link = "http://hoge.com"
      description = "fugafugafugafuga"

      rss = RSS::Maker.make("1.0")
      assert_nil(rss)
      
      rss = RSS::Maker.make("1.0") do |maker|
        maker.channel.about = about
        maker.channel.title = title
        maker.channel.link = link
        maker.channel.description = description
      end
      channel = rss.channel
      assert_equal(about, channel.about)
      assert_equal(title, channel.title)
      assert_equal(link, channel.link)
      assert_equal(description, channel.description)
      assert_equal(true, channel.items.Seq.lis.empty?)
      assert_nil(channel.image)
      assert_nil(channel.textinput)

      rss = RSS::Maker.make("1.0") do |maker|
        maker.channel.about = about
        maker.channel.title = title
        maker.channel.link = link
        maker.channel.description = description

        setup_dummy_image(maker)

        setup_dummy_textinput(maker)
      end
      channel = rss.channel
      assert_equal(about, channel.about)
      assert_equal(title, channel.title)
      assert_equal(link, channel.link)
      assert_equal(description, channel.description)
      assert(channel.items.Seq.lis.empty?)
      assert_equal(rss.image.about, channel.image.resource)
      assert_equal(rss.textinput.about, channel.textinput.resource)
    end

    def test_not_valid_channel
      about = "http://hoge.com"
      title = "fugafuga"
      link = "http://hoge.com"
      description = "fugafugafugafuga"

      assert_not_set_error("maker.channel", %w(about)) do
        RSS::Maker.make("1.0") do |maker|
          # maker.channel.about = about
          maker.channel.title = title
          maker.channel.link = link
          maker.channel.description = description
        end
      end

      assert_not_set_error("maker.channel", %w(title)) do
        RSS::Maker.make("1.0") do |maker|
          maker.channel.about = about
          # maker.channel.title = title
          maker.channel.link = link
          maker.channel.description = description
        end
      end

      assert_not_set_error("maker.channel", %w(link)) do
        RSS::Maker.make("1.0") do |maker|
          maker.channel.about = about
          maker.channel.title = title
          # maker.channel.link = link
          maker.channel.description = description
        end
      end

      assert_not_set_error("maker.channel", %w(description)) do
        RSS::Maker.make("1.0") do |maker|
          maker.channel.about = about
          maker.channel.title = title
          maker.channel.link = link
          # maker.channel.description = description
        end
      end
    end
    
    
    def test_image
      title = "fugafuga"
      link = "http://hoge.com"
      url = "http://hoge.com/hoge.png"

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        maker.channel.link = link
        
        maker.image.title = title
        maker.image.url = url
      end
      image = rss.image
      assert_equal(url, image.about)
      assert_equal(url, rss.channel.image.resource)
      assert_equal(title, image.title)
      assert_equal(link, image.link)
      assert_equal(url, image.url)

      assert_not_set_error("maker.channel", %w(about title description)) do
        RSS::Maker.make("1.0") do |maker|
          # setup_dummy_channel(maker)
          maker.channel.link = link
          
          maker.image.title = title
          maker.image.url = url
        end
      end
    end

    def test_not_valid_image
      title = "fugafuga"
      link = "http://hoge.com"
      url = "http://hoge.com/hoge.png"

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        maker.channel.link = link
        
        # maker.image.url = url
        maker.image.title = title
      end
      assert_nil(rss.channel.image)
      assert_nil(rss.image)

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        maker.channel.link = link
        
        maker.image.url = url
        # maker.image.title = title
      end
      assert_nil(rss.channel.image)
      assert_nil(rss.image)

      assert_not_set_error("maker.channel", %w(link)) do
        RSS::Maker.make("1.0") do |maker|
          setup_dummy_channel(maker)
          # maker.channel.link = link
          maker.channel.link = nil
          
          maker.image.url = url
          maker.image.title = title
        end
      end
    end
    
    def test_items
      title = "TITLE"
      link = "http://hoge.com/"
      description = "text hoge fuga"

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
      end
      assert(rss.items.empty?)

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        
        item = maker.items.new_item
        item.title = title
        item.link = link
        # item.description = description
      end
      assert_equal(1, rss.items.size)
      item = rss.items.first
      assert_equal(link, item.about)
      assert_equal(title, item.title)
      assert_equal(link, item.link)
      assert_nil(item.description)

      
      item_size = 5
      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        
        item_size.times do |i|
          item = maker.items.new_item
          item.title = "#{title}#{i}"
          item.link = "#{link}#{i}"
          item.description = "#{description}#{i}"
        end
        maker.items.do_sort = true
      end
      assert_equal(item_size, rss.items.size)
      rss.items.each_with_index do |item, i|
        assert_equal("#{link}#{i}", item.about)
        assert_equal("#{title}#{i}", item.title)
        assert_equal("#{link}#{i}", item.link)
        assert_equal("#{description}#{i}", item.description)
      end

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        
        item_size.times do |i|
          item = maker.items.new_item
          item.title = "#{title}#{i}"
          item.link = "#{link}#{i}"
          item.description = "#{description}#{i}"
        end
        maker.items.do_sort = Proc.new do |x, y|
          y.title[-1] <=> x.title[-1]
        end
      end
      assert_equal(item_size, rss.items.size)
      rss.items.reverse.each_with_index do |item, i|
        assert_equal("#{link}#{i}", item.about)
        assert_equal("#{title}#{i}", item.title)
        assert_equal("#{link}#{i}", item.link)
        assert_equal("#{description}#{i}", item.description)
      end
    end

    def test_not_valid_items
      title = "TITLE"
      link = "http://hoge.com/"

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        
        item = maker.items.new_item
        # item.title = title
        item.link = link
      end
      assert(rss.items.empty?)

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        
        item = maker.items.new_item
        item.title = title
        # item.link = link
      end
      assert(rss.items.empty?)
    end
    
    def test_textinput
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
      end
      textinput = rss.textinput
      assert_equal(link, textinput.about)
      assert_equal(link, rss.channel.textinput.resource)
      assert_equal(title, textinput.title)
      assert_equal(name, textinput.name)
      assert_equal(description, textinput.description)
      assert_equal(link, textinput.link)

      rss = RSS::Maker.make("1.0") do |maker|
        # setup_dummy_channel(maker)

        maker.textinput.link = link
        maker.textinput.title = title
        maker.textinput.description = description
        maker.textinput.name = name
      end
      assert_nil(rss)
    end
    
    def test_not_valid_textinput
      title = "fugafuga"
      description = "text hoge fuga"
      name = "hoge"
      link = "http://hoge.com"

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)

        # maker.textinput.link = link
        maker.textinput.title = title
        maker.textinput.description = description
        maker.textinput.name = name
      end
      assert_nil(rss.channel.textinput)
      assert_nil(rss.textinput)

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        
        maker.textinput.link = link
        # maker.textinput.title = title
        maker.textinput.description = description
        maker.textinput.name = name
      end
      assert_nil(rss.channel.textinput)
      assert_nil(rss.textinput)

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        
        maker.textinput.link = link
        maker.textinput.title = title
        # maker.textinput.description = description
        maker.textinput.name = name
      end
      assert_nil(rss.channel.textinput)
      assert_nil(rss.textinput)

      rss = RSS::Maker.make("1.0") do |maker|
        setup_dummy_channel(maker)
        
        maker.textinput.link = link
        maker.textinput.title = title
        maker.textinput.description = description
        # maker.textinput.name = name
      end
      assert_nil(rss.channel.textinput)
      assert_nil(rss.textinput)
    end

  end
end
