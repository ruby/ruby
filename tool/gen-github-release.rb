#!/usr/bin/env ruby

require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "octokit"
  gem "faraday-retry"
  gem "nokogiri"
end

require "open-uri"

Octokit.configure do |c|
  c.access_token = ENV['GITHUB_TOKEN']
  c.auto_paginate = true
  c.per_page = 100
end

client = Octokit::Client.new

diff = client.compare("ruby/ruby", ARGV[0], ARGV[1])
diff[:commits].each do |c|
  if c[:commit][:message] =~ /\[Backport #(\d*)\]/
    url = "https://bugs.ruby-lang.org/issues/#{$1}"
    title = Nokogiri::HTML(URI.open(url)).title
    title.gsub!(/ - Ruby master - Ruby Issue Tracking System/, "")
  elsif c[:commit][:message] =~ /\(#(\d*)\)/
    url = "https://github.com/ruby/ruby/pull/#{$1}"
    title = Nokogiri::HTML(URI.open(url)).title
    title.gsub!(/ · ruby\/ruby · GitHub/, "")
  else
    next
  end
  puts "* [#{title}](#{url})"
rescue OpenURI::HTTPError
  puts "Error: #{url}"
end

