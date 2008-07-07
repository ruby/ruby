require "rss-testcase"

require "rss/maker"

module RSS
  class TestMaker09 < TestCase

    def test_rss
      rss = RSS::Maker.make("0.91")
      assert_nil(rss)
      
      rss = RSS::Maker.make("0.9") do |maker|
        setup_dummy_channel(maker)
      end
      assert_equal("0.91", rss.rss_version)
      
      rss = RSS::Maker.make("0.91") do |maker|
        setup_dummy_channel(maker)
      end
      assert_equal("0.91", rss.rss_version)

      
      rss = RSS::Maker.make("0.91") do |maker|
        setup_dummy_channel(maker)
        
        maker.encoding = "EUC-JP"
      end
      assert_equal("0.91", rss.rss_version)
      assert_equal("EUC-JP", rss.encoding)

      rss = RSS::Maker.make("0.91") do |maker|
        setup_dummy_channel(maker)
        
        maker.standalone = "yes"
      end
      assert_equal("0.91", rss.rss_version)
      assert_equal("yes", rss.standalone)

      rss = RSS::Maker.make("0.91") do |maker|
        setup_dummy_channel(maker)
        
        maker.encoding = "EUC-JP"
        maker.standalone = "yes"
      end
      assert_equal("0.91", rss.rss_version)
      assert_equal("EUC-JP", rss.encoding)
      assert_equal("yes", rss.standalone)
    end

    def test_channel
      title = "fugafuga"
      link = "http://hoge.com"
      description = "fugafugafugafuga"
      language = "ja"
      copyright = "foo"
      managingEditor = "bar"
      webMaster = "web master"
      rating = '(PICS-1.1 "http://www.rsac.org/ratingsv01.html" l gen true comment "RSACi North America Server" for "http://www.rsac.org" on "1996.04.16T08:15-0500" r (n 0 s 0 v 0 l 0))'
      docs = "http://foo.com/doc"
      skipDays = [
        "Sunday",
        "Monday",
      ]
      skipHours = [
        "0",
        "13",
      ]
      pubDate = Time.now
      lastBuildDate = Time.now
      
      rss = RSS::Maker.make("0.91") do |maker|
        maker.channel.title = title
        maker.channel.link = link
        maker.channel.description = description
        maker.channel.language = language
        maker.channel.copyright = copyright
        maker.channel.managingEditor = managingEditor
        maker.channel.webMaster = webMaster
        maker.channel.rating = rating
        maker.channel.docs = docs
        maker.channel.pubDate = pubDate
        maker.channel.lastBuildDate = lastBuildDate

        skipDays.each do |day|
          maker.channel.skipDays.new_day do |new_day|
            new_day.content = day
          end
        end
        skipHours.each do |hour|
          maker.channel.skipHours.new_hour do |new_hour|
            new_hour.content = hour
          end
        end
      end
      channel = rss.channel
      
      assert_equal(title, channel.title)
      assert_equal(link, channel.link)
      assert_equal(description, channel.description)
      assert_equal(language, channel.language)
      assert_equal(copyright, channel.copyright)
      assert_equal(managingEditor, channel.managingEditor)
      assert_equal(webMaster, channel.webMaster)
      assert_equal(rating, channel.rating)
      assert_equal(docs, channel.docs)
      assert_equal(pubDate, channel.pubDate)
      assert_equal(pubDate, channel.date)
      assert_equal(lastBuildDate, channel.lastBuildDate)

      skipDays.each_with_index do |day, i|
        assert_equal(day, channel.skipDays.days[i].content)
      end
      skipHours.each_with_index do |hour, i|
        assert_equal(hour.to_i, channel.skipHours.hours[i].content)
      end
      
      assert(channel.items.empty?)
      assert_nil(channel.image)
      assert_nil(channel.textInput)
    end

    def test_not_valid_channel
      title = "fugafuga"
      link = "http://hoge.com"
      description = "fugafugafugafuga"
      language = "ja"

      assert_not_set_error("maker.channel", %w(title)) do
        RSS::Maker.make("0.91") do |maker|
          # maker.channel.title = title
          maker.channel.link = link
          maker.channel.description = description
          maker.channel.language = language
        end
      end

      assert_not_set_error("maker.channel", %w(link)) do
        RSS::Maker.make("0.91") do |maker|
          maker.channel.title = title
          # maker.channel.link = link
          maker.channel.link = nil
          maker.channel.description = description
          maker.channel.language = language
        end
      end

      assert_not_set_error("maker.channel", %w(description)) do
        RSS::Maker.make("0.91") do |maker|
          maker.channel.title = title
          maker.channel.link = link
          # maker.channel.description = description
          maker.channel.language = language
        end
      end

      assert_not_set_error("maker.channel", %w(language)) do
        RSS::Maker.make("0.91") do |maker|
          maker.channel.title = title
          maker.channel.link = link
          maker.channel.description = description
          # maker.channel.language = language
        end
      end
    end
    
    def test_image
      title = "fugafuga"
      link = "http://hoge.com"
      url = "http://hoge.com/hoge.png"
      width = "144"
      height = "400"
      description = "an image"

      rss = RSS::Maker.make("0.91") do |maker|
        setup_dummy_channel(maker)
        maker.channel.link = link
        
        maker.image.title = title
        maker.image.url = url
        maker.image.width = width
        maker.image.height = height
        maker.image.description = description
      end
      image = rss.image
      assert_equal(title, image.title)
      assert_equal(link, image.link)
      assert_equal(url, image.url)
      assert_equal(width.to_i, image.width)
      assert_equal(height.to_i, image.height)
      assert_equal(description, image.description)

      assert_not_set_error("maker.channel", %w(description title language)) do
        RSS::Maker.make("0.91") do |maker|
          # setup_dummy_channel(maker)
          maker.channel.link = link
        
          maker.image.title = title
          maker.image.url = url
          maker.image.width = width
          maker.image.height = height
          maker.image.description = description
        end
      end
    end

    def test_not_valid_image
      title = "fugafuga"
      link = "http://hoge.com"
      url = "http://hoge.com/hoge.png"
      width = "144"
      height = "400"
      description = "an image"

      rss = RSS::Maker.make("0.91") do |maker|
        setup_dummy_channel(maker)
        maker.channel.link = link
        
        # maker.image.title = title
        maker.image.url = url
        maker.image.width = width
        maker.image.height = height
        maker.image.description = description
      end
      assert_nil(rss.channel.image)

      assert_not_set_error("maker.channel", %w(link)) do
        RSS::Maker.make("0.91") do |maker|
          setup_dummy_channel(maker)
          # maker.channel.link = link
          maker.channel.link = nil
        
          maker.image.title = title
          maker.image.url = url
          maker.image.width = width
          maker.image.height = height
          maker.image.description = description
        end
      end

      rss = RSS::Maker.make("0.91") do |maker|
        setup_dummy_channel(maker)
        maker.channel.link = link
        
        maker.image.title = title
        # maker.image.url = url
        maker.image.width = width
        maker.image.height = height
        maker.image.description = description
      end
      assert_nil(rss.channel.image)
    end
    
    def test_items
      title = "TITLE"
      link = "http://hoge.com/"
      description = "text hoge fuga"

      rss = RSS::Maker.make("0.91") do |maker|
        setup_dummy_channel(maker)
      end
      assert(rss.channel.items.empty?)

      rss = RSS::Maker.make("0.91") do |maker|
        setup_dummy_channel(maker)
        
        maker.items.new_item do |item|
          item.title = title
          item.link = link
          # item.description = description
        end
      end
      assert_equal(1, rss.channel.items.size)
      item = rss.channel.items.first
      assert_equal(title, item.title)
      assert_equal(link, item.link)
      assert_nil(item.description)


      item_size = 5
      rss = RSS::Maker.make("0.91") do |maker|
        setup_dummy_channel(maker)
        
        item_size.times do |i|
          maker.items.new_item do |item|
            item.title = "#{title}#{i}"
            item.link = "#{link}#{i}"
            item.description = "#{description}#{i}"
          end
        end
        maker.items.do_sort = true
      end
      assert_equal(item_size, rss.items.size)
      rss.channel.items.each_with_index do |item, i|
        assert_equal("#{title}#{i}", item.title)
        assert_equal("#{link}#{i}", item.link)
        assert_equal("#{description}#{i}", item.description)
      end

      rss = RSS::Maker.make("0.91") do |maker|
        setup_dummy_channel(maker)
        
        item_size.times do |i|
          maker.items.new_item do |item|
            item.title = "#{title}#{i}"
            item.link = "#{link}#{i}"
            item.description = "#{description}#{i}"
          end
        end
        maker.items.do_sort = Proc.new do |x, y|
          y.title[-1] <=> x.title[-1]
        end
      end
      assert_equal(item_size, rss.items.size)
      rss.channel.items.reverse.each_with_index do |item, i|
        assert_equal("#{title}#{i}", item.title)
        assert_equal("#{link}#{i}", item.link)
        assert_equal("#{description}#{i}", item.description)
      end
    end

    def test_textInput
      title = "fugafuga"
      description = "text hoge fuga"
      name = "hoge"
      link = "http://hoge.com"

      rss = RSS::Maker.make("0.91") do |maker|
        setup_dummy_channel(maker)

        maker.textinput.title = title
        maker.textinput.description = description
        maker.textinput.name = name
        maker.textinput.link = link
      end
      textInput = rss.channel.textInput
      assert_equal(title, textInput.title)
      assert_equal(description, textInput.description)
      assert_equal(name, textInput.name)
      assert_equal(link, textInput.link)

      rss = RSS::Maker.make("0.91") do |maker|
        # setup_dummy_channel(maker)

        maker.textinput.title = title
        maker.textinput.description = description
        maker.textinput.name = name
        maker.textinput.link = link
      end
      assert_nil(rss)
    end
    
    def test_not_valid_textInput
      title = "fugafuga"
      description = "text hoge fuga"
      name = "hoge"
      link = "http://hoge.com"

      rss = RSS::Maker.make("0.91") do |maker|
        setup_dummy_channel(maker)

        # maker.textinput.title = title
        maker.textinput.description = description
        maker.textinput.name = name
        maker.textinput.link = link
      end
      assert_nil(rss.channel.textInput)

      rss = RSS::Maker.make("0.91") do |maker|
        setup_dummy_channel(maker)
        
        maker.textinput.title = title
        # maker.textinput.description = description
        maker.textinput.name = name
        maker.textinput.link = link
      end
      assert_nil(rss.channel.textInput)

      rss = RSS::Maker.make("0.91") do |maker|
        setup_dummy_channel(maker)
        
        maker.textinput.title = title
        maker.textinput.description = description
        # maker.textinput.name = name
        maker.textinput.link = link
      end
      assert_nil(rss.channel.textInput)

      rss = RSS::Maker.make("0.91") do |maker|
        setup_dummy_channel(maker)
        
        maker.textinput.title = title
        maker.textinput.description = description
        maker.textinput.name = name
        # maker.textinput.link = link
      end
      assert_nil(rss.channel.textInput)
    end
  end
end
