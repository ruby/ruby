# -*- tab-width: 2 -*- vim: ts=2

require "test/unit"
require "rss/parser"
require "rss/1.0"
require "rss/2.0"
require "common"

class TestAccessor < Test::Unit::TestCase
	include TestRSSMixin
	
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
