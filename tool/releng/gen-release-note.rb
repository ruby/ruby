#!/usr/bin/env ruby
require 'open-uri'
require 'time'
require 'yaml'

# Confirm current directory is www.ruby-lang.org's working directory
def confirm_w_r_l_o_wd
  File.foreach('.git/config') do |line|
    return true if line.include?('git@github.com:ruby/www.ruby-lang.org.git')
  end
  abort "Run this script in www.ruby-lang.org's working directory"
end
confirm_w_r_l_o_wd

%w[
    https://hackmd.io/@naruse/ruby-relnote-en/download
    https://hackmd.io/@naruse/ruby-relnote-ja/download
].each do |url|
  src = URI(url).read
  src.gsub!(/[ \t]+$/, "")
  src.sub!(/\s+\z/, "\n")
  src.sub!(/^breaks: false\n/, '')
  if /^\{% assign release = site.data.releases \| where: "version", "([^"]+)" \| first %\}/ =~ src
    version = $1
  else
    abort %[#{url} doesn't include `{% assign release = site.data.releases | where: "version", "<version>" | first %}`]
  end
  puts "#{url} -> #{version}"


  # Write release note article
  path = Time.parse(src[/^date: (.*)/, 1]).
    strftime("./#{src[/^lang: (\w+)/, 1]}/news/_posts/%Y-%m-%d-ruby-#{version.tr('.', '-')}-released.md")
  puts path
  File.write(path, src)
end
