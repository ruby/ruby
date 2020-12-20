#!/usr/bin/env ruby
require "open-uri"
require "yaml"

# Confirm current directory is www.ruby-lang.org's working directory
def confirm_w_r_l_o_wd
  File.foreach('.git/config') do |line|
    return true if line.include?('git@github.com:ruby/www.ruby-lang.org.git')
  end
  abort "Run this script in www.ruby-lang.org's working directory"
end
confirm_w_r_l_o_wd

releases = YAML.load_file('_data/releases.yml')

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

  release = releases.find{|rel|rel['version'] == version}
  unless release
   abort "#{version} is not found in '_data/releases.yml'"
  end

  # Write release note article
  lang = url[/ja|en/]
  if %r<\A/en/news/(\d+/\d+/\d+/ruby-[\w\-]+-released)> =~ release['post']
    path = "#{lang}/news/_posts/#{$1.tr('/', '-')}.md"
  else
    abort "unexpected path pattern '#{release['post']}'"
  end
  puts path
  File.write(path, src)
end
