#!/usr/bin/env ruby
require "open-uri"
require "yaml"

lang = ARGV.shift
unless lang
  abort "usage: #$1 {en,ja} | pbcopy"
end

# Confirm current directory is www.ruby-lang.org's working directory
def confirm_w_r_l_o_wd
  File.foreach('.git/config') do |line|
    return true if line.include?('git@github.com:ruby/www.ruby-lang.org.git')
  end
  abort "Run this script in www.ruby-lang.org's working directory"
end
confirm_w_r_l_o_wd

releases = YAML.load_file('_data/releases.yml')

url = "https://hackmd.io/@naruse/ruby-relnote-#{lang}/download"
src = URI(url).read
src.gsub!(/[ \t]+$/, "")
src.sub!(/(?<!\n)\z/, "\n")
src.sub!(/^breaks: false\n/, '')

if /^\{% assign release = site.data.releases \| where: "version", "([^"]+)" \| first %\}/ =~ src
  version = $1
else
  abort %[#{url} doesn't include `{% assign release = site.data.releases | where: "version", "<version>" | first %}`]
end

release = releases.find{|rel|rel['version'] == version}
unless release
  abort "#{version} is not found in '_data/releases.yml'"
end

src.gsub!(/^{% assign .*\n/, '')
src.gsub!(/\{\{(.*?)\}\}/) do
  var = $1.strip
  case var
  when /\Arelease\.(.*)/
    val =  release.dig(*$1.split('.'))
    raise "invalid variable '#{var}'" unless val
  else
    raise "unknown variable '#{var}'"
  end
  val
end
puts src
