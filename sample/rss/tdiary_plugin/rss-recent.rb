# rss-recent.rb: RSS recent plugin 
#
# rss_recnet: show recnet list from RSS
#   parameters (default):
#      url: URL of RSS
#      max: max of list itmes(5)
#      cache_time: cache time(second) of RSS(60*60)
#      
#
# Copyright (c) 2003 Kouhei Sutou <kou@cozmixng.org>
# Distributed under the GPL
#

require "rss/rss"

RSS_RECENT_FIELD_SEPARATOR = "\0"
RSS_RECENT_VERSION = "0.0.2"
RSS_RECENT_CONTENT_TYPE = {
	"User-Agent" => "tDiary RSS recent plugin version #{RSS_RECENT_VERSION}. " <<
	"Using RSS parser version is #{::RSS::VERSION}."
}


def rss_recent(url, max=5, cache_time=3600)
	cache_file = "#{@cache_path}/rss-recent.#{CGI.escape(url)}"

	rss_recent_cache_rss(url, cache_file, cache_time.to_i)
	
	return '' unless test(?r, cache_file)

	rv = "<ul>\n"
	File.open(cache_file) do |f|
		max.to_i.times do
			title = f.gets(RSS_RECENT_FIELD_SEPARATOR)
			break if title.nil?
			rv << '<li>'
			link = f.gets(RSS_RECENT_FIELD_SEPARATOR)
			unless link.nil?
				rv << %Q!<a href="#{CGI.escapeHTML(link.chomp(RSS_RECENT_FIELD_SEPARATOR))}">!
			end
			rv << CGI::escapeHTML(title.chomp(RSS_RECENT_FIELD_SEPARATOR))
			rv << '</a>' unless link.nil?
			rv << "</li>\n"
    end
	end
	rv << "</ul>\n"

	rv
end

class InvalidResourceError < StandardError; end

def rss_recent_cache_rss(url, cache_file, cache_time)

	begin
		raise if Time.now > File.mtime(cache_file) + cache_time
	rescue
		require 'net/http'
		require 'uri/generic'
		require 'rss/parser'
		require 'rss/1.0'
		require 'rss/2.0'
		
		begin
			ur = URI.parse(url)

			raise URI::InvalidURIError if ur.scheme != "http"

			rss_source = rss_recent_fetch_rss(ur)

			# parse RSS
			rss = ::RSS::Parser.parse(rss_source, false)
			raise ::RSS::Error if rss.nil?

			# pre processing
			begin
				rss.output_encoding = charset
			rescue ::RSS::UnknownConversionMethodError
			end

			tlary = rss.items.collect{|item| [item.title, item.link]}
			rss_recent_write_to_cache(cache_file, tlary)

		rescue URI::InvalidURIError
			rss_recent_write_to_cache(cache_file, [['Invalid URI', url]])
		rescue InvalidResourceError, ::RSS::Error
			rss_recent_write_to_cache(cache_file, [['Invalid Resource', url]])
		end
	end

end

def rss_recent_fetch_rss(uri)
	rss = ''
	begin
		Net::HTTP.start(uri.host, uri.port || 80) do |http|
			path = uri.path
			path << "?#{uri.query}" if uri.query
			req = http.request_get(path)
			raise InvalidResourceError unless req.code == "200"
			rss << req.body
		end
	rescue TimeoutError, SocketError
		raise InvalidResourceError
	end
	rss
end

def rss_recent_write_to_cache(cache_file, array_of_titles_and_links)
	File.open(cache_file, 'w') do |f|
		f.flock(File::LOCK_EX)
		array_of_titles_and_links.each do |title, link|
			f << "#{title}#{RSS_RECENT_FIELD_SEPARATOR}"
			f << "#{link}#{RSS_RECENT_FIELD_SEPARATOR}"
		end
		f.flock(File::LOCK_UN)
	end
end
