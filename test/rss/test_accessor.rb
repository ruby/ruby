require "rss-testcase"

require "rss/1.0"
require "rss/2.0"

module RSS
  class TestAccessor < TestCase
    
    def test_date
      channel = Rss::Channel.new
      channel.do_validate = false
      channel.pubDate = nil
      assert_nil(channel.pubDate)
      
      time = Time.now
      channel.pubDate = time
      assert_equal(time, channel.pubDate)
      
      channel.pubDate = nil
      assert_nil(channel.pubDate)
    end
    
  end
end
