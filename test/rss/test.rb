#!/usr/bin/env ruby

require "rbconfig"
require "rss/parser"

c = Config::CONFIG
ruby = File.join(c['bindir'], c['ruby_install_name'])

RSS::AVAILABLE_PARSERS.each do |parser|
	puts "------------------------------------"
	puts "Using #{parser}"
	puts "------------------------------------"
	Dir.glob(ARGV.shift || "test/test_*") do |file|
		puts(`#{ruby} #{if $DEBUG then '-d' end} -I. -I./lib test/each_parser.rb #{parser} #{file} #{ARGV.join(' ')}`)
	end
end
