#!/usr/bin/env ruby

require "nkf"
class String
  # From tdiary.rb
  def shorten( len = 120 )
    lines = NKF::nkf( "-e -m0 -f#{len}", self.gsub( /\n/, ' ' ) ).split( /\n/ )
    lines[0].concat( '...' ) if lines[0] and lines[1]
    lines[0]
  end
end

require "rss/1.0"
require "rss/2.0"
require "rss/dublincore"

items = []
verbose = false

def error(exception)
  mark = "=" * 20
  mark = "#{mark} error #{mark}"
  puts mark
  puts exception.class
  puts exception.message
  puts exception.backtrace
  puts mark
end
before_time = Time.now
ARGV.each do |fname|
  if fname == '-v'
    verbose = true
    next
  end
  rss = nil
  f = File.new(fname).read
  begin
    ## do validate parse
    rss = RSS::Parser.parse(f)
  rescue RSS::InvalidRSSError
    error($!) if verbose
    ## do non validate parse for invalid RSS 1.0
    begin
      rss = RSS::Parser.parse(f, false)
    rescue RSS::Error
      ## invalid RSS.
      error($!) if verbose
    end
  rescue RSS::Error
    error($!) if verbose
  end
  if rss.nil?
    puts "#{fname} does not include RSS 1.0 or 0.9x/2.0"
  else
    begin
      rss.output_encoding = "euc-jp"
    rescue RSS::UnknownConversionMethodError
      error($!) if verbose
    end
    rss.items.each do |item|
      if item.respond_to?(:pubDate) and item.pubDate
        class << item
          alias_method(:dc_date, :pubDate)
        end
      end
      if item.respond_to?(:dc_date) and item.dc_date
        items << [rss.channel, item]
      end
    end
  end
end
processing_time = Time.now - before_time

items.sort do |x, y|
  y[1].dc_date <=> x[1].dc_date
end[0..20].each do |channel, item|
  puts "#{item.dc_date.localtime.iso8601}: " <<
    "#{channel.title}: #{item.title}"
  puts " Description: #{item.description.shorten(50)}" if item.description
end

puts "Used XML parser: #{RSS::Parser.default_parser}"
puts "Processing time: #{processing_time}s"
