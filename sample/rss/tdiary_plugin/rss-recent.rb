# -*- indent-tabs-mode: t -*-
# rss-recent.rb: RSS recent plugin 
#
# options:
#   @options['rss-recent.use-image-link'] : use image as link
#                                           instead of text if available.
#
# rss_recnet: show recnet list from RSS
#   parameters (default):
#      url: URL of RSS
#      max: max of list itmes(5)
#      cache_time: cache time(second) of RSS(60*60)
#
#
# Copyright (c) 2003-2005 Kouhei Sutou <kou@cozmixng.org>
# Distributed under the GPL
#

require "rss/rss"

RSS_RECENT_FIELD_SEPARATOR = "\0"
RSS_RECENT_ENTRY_SEPARATOR = "\1"
RSS_RECENT_VERSION = "0.0.6"
RSS_RECENT_HTTP_HEADER = {
	"User-Agent" => "tDiary RSS recent plugin version #{RSS_RECENT_VERSION}. " <<
		"Using RSS parser version is #{::RSS::VERSION}.",
}

def rss_recent(url, max=5, cache_time=3600)
	url.untaint

	cache_file = "#{@cache_path}/rss-recent.#{CGI.escape(url)}"

	rss_recent_cache_rss(url, cache_file, cache_time.to_i)
	
	return '' unless test(?r, cache_file)

	rv = "<div class='rss-recent'>\n"

	site_info, *infos = rss_recent_read_from_cache(cache_file)
  
	if site_info
		title, url, time, image = site_info
		content = rss_recent_entry_to_html(title, url, time, image)
		rv << "<div class='rss-recent-title'>\n"
		rv << "<span class='#{rss_recent_modified_class(time)}'>#{content}</span>\n"
		rv << "</div>\n"
	end
  
	have_entry = infos.size > 0 && max > 0
  
	rv << "<ul>\n" if have_entry
	i = 0
	infos.each do |title, url, time, image|
		break if i >= max
		next if title.nil?
		rv << '<li>'
		rv << %Q[<span class="#{rss_recent_modified_class(time)}">]
		rv << rss_recent_entry_to_html(title, url, time, image)
		rv << %Q[</span>]
		rv << "</li>\n"
		i += 1
	end

	rv << "</ul>\n" if have_entry

	rv << "</div>\n"

	rv
end

class InvalidResourceError < StandardError; end

def rss_recent_cache_rss(url, cache_file, cache_time)

	cached_time = nil
	cached_time = File.mtime(cache_file) if File.exist?(cache_file)

	if cached_time.nil? or Time.now > cached_time + cache_time
		require 'time'
		require 'open-uri'
		require 'net/http'
		require 'uri/generic'
		require 'rss/parser'
		require 'rss/1.0'
		require 'rss/2.0'
		require 'rss/dublincore'
		begin
			require 'rss/image'
		rescue LoadError
		end
		
		begin
			uri = URI.parse(url)

			raise URI::InvalidURIError if uri.scheme != "http"

			rss_source = rss_recent_fetch_rss(uri, cached_time)
			
			raise InvalidResourceError if rss_source.nil?

			# parse RSS
			rss = ::RSS::Parser.parse(rss_source, false)
			raise ::RSS::Error if rss.nil?

			# pre processing
			begin
				rss.output_encoding = @conf.charset || charset
			rescue ::RSS::UnknownConversionMethodError
			end

			rss_infos = []
			rss.items.each do |item|
				rss_recent_pubDate_to_dc_date(item)
				if item.respond_to?(:image_item) and item.image_item
					image = item.image_item.about
				else
					image = nil
				end
				rss_infos << [item.title, item.link, item.dc_date, image]
			end
			rss_recent_pubDate_to_dc_date(rss.channel)
			rss_infos.unshift([
				rss.channel.title,
				rss.channel.link,
				rss.channel.dc_date ||
					rss.items.collect{|item| item.dc_date}.compact.first,
				rss.image && rss.image.url,
			])
			rss_recent_write_to_cache(cache_file, rss_infos)

		rescue URI::InvalidURIError
			rss_recent_write_to_cache(cache_file, [['Invalid URI', url]])
		rescue InvalidResourceError, ::RSS::Error
			rss_recent_write_to_cache(cache_file, [['Invalid Resource', url]])
		end
	end

end

def rss_recent_fetch_rss(uri, cache_time)
	rss = nil
	begin
		uri.open(rss_recent_http_header(cache_time)) do |f|
			case f.status.first
			when "200"
				rss = f.read
				# STDERR.puts "Got RSS of #{uri}"
			when "304"
				# not modified
				# STDERR.puts "#{uri} does not modified"
			else
				raise InvalidResourceError
			end
		end
	rescue TimeoutError, SocketError, StandardError,
		SecurityError # occured in redirect
		raise InvalidResourceError
	end
	rss
end

def rss_recent_http_header(cache_time)
	header = RSS_RECENT_HTTP_HEADER.dup
	if cache_time.respond_to?(:rfc2822)
		header["If-Modified-Since"] = cache_time.rfc2822
	end
	header
end

def rss_recent_write_to_cache(cache_file, rss_infos)
	File.open(cache_file, 'w') do |f|
		f.flock(File::LOCK_EX)
		rss_infos.each do |info|
			f << info.join(RSS_RECENT_FIELD_SEPARATOR)
			f << RSS_RECENT_ENTRY_SEPARATOR
		end
		f.flock(File::LOCK_UN)
	end
end

def rss_recent_read_from_cache(cache_file)
	require 'time'
	infos = []
	File.open(cache_file) do |f|
		while info = f.gets(RSS_RECENT_ENTRY_SEPARATOR)
			info = info.chomp(RSS_RECENT_ENTRY_SEPARATOR)
			infos << info.split(RSS_RECENT_FIELD_SEPARATOR)
		end
	end
	infos.collect do |title, url, time, image|
		[
			rss_recent_convert(title),
			rss_recent_convert(url),
			rss_recent_convert(time) {|t| Time.parse(t)},
			rss_recent_convert(image),
		]
	end
end

def rss_recent_convert(str)
	if str.nil? or str.empty?
		nil
	else
		if block_given?
			yield str
		else
			str
		end
	end
end

def rss_recent_entry_to_html(title, url, time, image=nil)
	rv = ""
	unless url.nil?
		rv << %Q[<a href="#{CGI.escapeHTML(url)}" title="#{CGI.escapeHTML(title)}]
		rv << %Q[ (#{CGI.escapeHTML(time.localtime.to_s)})] unless time.nil?
		rv << %Q[">]
	end
	if image and @options['rss-recent.use-image-link']
		rv << %Q[<img src="#{CGI::escapeHTML(image)}"]
		rv << %Q[ title="#{CGI.escapeHTML(title)}"]
		rv << %Q[ alt="site image"]
		rv << %Q[>\n]
	else
		rv << CGI::escapeHTML(title)
	end
	rv << '</a>' unless url.nil?
	rv << "(#{rss_recent_modified(time)})"
	rv
end

# from RWiki
def rss_recent_modified(t)
	return '-' unless t
	dif = (Time.now - t).to_i
	dif = dif / 60
	return "#{dif}m" if dif <= 60
	dif = dif / 60
	return "#{dif}h" if dif <= 24
	dif = dif / 24
	return "#{dif}d"
end

# from RWiki
def rss_recent_modified_class(t)
	return 'dangling' unless t
	dif = (Time.now - t).to_i
	dif = dif / 60
	return "modified-hour" if dif <= 60
	dif = dif / 60
	return "modified-today" if dif <= 24
	dif = dif / 24
	return "modified-month" if dif <= 30
	return "modified-year" if dif <= 365
	return "modified-old"
end

def rss_recent_pubDate_to_dc_date(target)
	if target.respond_to?(:pubDate)
		class << target
			alias_method(:dc_date, :pubDate)
		end
	end
end

add_conf_proc('rss-recent', label_rss_recent_title) do
	item = 'rss-recent.use-image-link'
	if @mode == 'saveconf'
		@conf[item] = (@cgi.params[item][0] == 't')
	end

	<<-HTML
	<div class"body">
		<h3 class="subtitle">#{label_rss_recent_use_image_link_title}</h3>
		<p>#{label_rss_recent_use_image_link_description}</p>
		<p>
			<select name=#{item}>
				<option value="f"#{@conf[item] ? '' : ' selected'}>
					#{label_rss_recent_not_use_image_link}
				</option>
				<option value="t"#{@conf[item] ? ' selected' : ''}>
					#{label_rss_recent_use_image_link}
				</option>
			</select>
		</p>
	</div>
	HTML
end
