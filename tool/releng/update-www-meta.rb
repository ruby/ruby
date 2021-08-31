#!/usr/bin/env ruby
require "open-uri"
require "yaml"

class Tarball
  attr_reader :version, :size, :sha1, :sha256, :sha512

  def initialize(version, url, size, sha1, sha256, sha512)
    @url = url
    @size = size
    @sha1 = sha1
    @sha256 = sha256
    @sha512 = sha512
    @version = version
    @xy = version[/\A\d+\.\d+/]
  end

  def gz?;  @url.end_with?('.gz'); end
  def zip?; @url.end_with?('.zip'); end
  def xz?;  @url.end_with?('.xz'); end

  def ext; @url[/(?:zip|tar\.(?:gz|xz))\z/]; end

  def to_md
    <<eom
* <https://cache.ruby-lang.org/pub/ruby/#{@xy}/ruby-#{@version}.#{ext}>

      SIZE:   #{@size} bytes
      SHA1:   #{@sha1}
      SHA256: #{@sha256}
      SHA512: #{@sha512}
eom
  end

  # * /home/naruse/obj/ruby-trunk/tmp/ruby-2.6.0-preview3.tar.gz
  #   SIZE:   17116009 bytes
  #   SHA1:   21f62c369661a2ab1b521fd2fa8191a4273e12a1
  #   SHA256: 97cea8aa63dfa250ba6902b658a7aa066daf817b22f82b7ee28f44aec7c2e394
  #   SHA512: 1e2042324821bb4e110af7067f52891606dcfc71e640c194ab1c117f0b941550e0b3ac36ad3511214ac80c536b9e5cfaf8789eec74cf56971a832ea8fc4e6d94
  def self.parse(wwwdir, version)
    unless /\A(\d+)\.(\d+)\.(\d+)(?:-(?:preview|rc)\d+)?\z/ =~ version
      raise "unexpected version string '#{version}'"
    end
    x = $1.to_i
    y = $2.to_i
    z = $3.to_i
    # previous tag for git diff --shortstat
    # It's only for x.y.0 release
    if z != 0
      prev_tag = nil
    elsif y != 0
      prev_tag = "v#{x}_#{y-1}_0"
      prev_ver = "#{x}.#{y-1}.0"
    elsif x == 3 && y == 0 && z == 0
      prev_tag = "v2_7_0"
      prev_ver = "2.7.0"
    else
      raise "unexpected version for prev_ver '#{version}'"
    end

    uri = "https://cache.ruby-lang.org/pub/tmp/ruby-info-#{version}-draft.yml"
    info = YAML.load(URI(uri).read)
    if info.size != 1
      raise "unexpected info.yml '#{uri}'"
    end
    tarballs = []
    info[0]["size"].each_key do |ext|
      url = info[0]["url"][ext]
      size = info[0]["size"][ext]
      sha1 = info[0]["sha1"][ext]
      sha256 = info[0]["sha256"][ext]
      sha512 = info[0]["sha512"][ext]
      tarball = Tarball.new(version, url, size, sha1, sha256, sha512)
      tarballs << tarball
    end

    if prev_tag
      # show diff shortstat
      tag = "v#{version.gsub(/[.\-]/, '_')}"
      rubydir = File.expand_path(File.join(__FILE__, '../../../'))
      puts %`git -C #{rubydir} diff --shortstat #{prev_tag}..#{tag}`
      stat = `git -C #{rubydir} diff --shortstat #{prev_tag}..#{tag}`
      files_changed, insertions, deletions = stat.scan(/\d+/)
    end

    xy = version[/\A\d+\.\d+/]
    #puts "## Download\n\n"
    #tarballs.each do |tarball|
    #  puts tarball.to_md
    #end
    update_branches_yml(version, xy, wwwdir)
    update_downloads_yml(version, xy, wwwdir)
    update_releases_yml(version, xy, tarballs, wwwdir, files_changed, insertions, deletions)
  end

  def self.update_branches_yml(ver, xy, wwwdir)
    filename = "_data/branches.yml"
    data = File.read(File.join(wwwdir, filename))
    if data.include?("\n- name: #{xy}\n")
      data.sub!(/\n- name: #{Regexp.escape(xy)}\n(?:  .*\n)*/) do |node|
        unless ver.include?("-")
          # assume this is X.Y.0 release
          node.sub!(/^  status: preview\n/, "  status: normal maintenance\n")
          node.sub!(/^  date:\n/, "  date: #{Time.now.year}-12-25\n")
        end
        node
      end
    else
      if ver.include?("-")
        status = "preview"
        year = nil
      else
        status = "normal maintenance"
        year = Time.now.year
      end
      entry = <<eom
- name: #{xy}
  status: #{status}
  date:#{ year && " #{year}-12-25" }
  eol_date:

eom
      data.sub!(/(?=^- name)/, entry)
    end
    File.write(File.join(wwwdir, filename), data)
  end

  def self.update_downloads_yml(ver, xy, wwwdir)
    filename = "_data/downloads.yml"
    data = File.read(File.join(wwwdir, filename))

    if /^preview:\n\n(?:  .*\n)*  - #{Regexp.escape(xy)}\./ =~ data
      if ver.include?("-")
        data.sub!(/^  - #{Regexp.escape(xy)}\..*/, "  - #{ver}")
      else
        data.sub!(/^  - #{Regexp.escape(xy)}\..*\n/, "")
        data.sub!(/(?<=^stable:\n\n)/, "  - #{ver}\n")
      end
    else
      unless data.sub!(/^  - #{Regexp.escape(xy)}\..*/, "  - #{ver}")
        if ver.include?("-")
          data.sub!(/(?<=^preview:\n\n)/, "  - #{ver}\n")
        else
          data.sub!(/(?<=^stable:\n\n)/, "  - #{ver}\n")
        end
      end
    end
    File.write(File.join(wwwdir, filename), data)
  end

  def self.update_releases_yml(ver, xy, ary, wwwdir, files_changed, insertions, deletions)
    filename = "_data/releases.yml"
    data = File.read(File.join(wwwdir, filename))

    date = Time.now.utc # use utc to use previous day in midnight
    entry = <<eom
- version: #{ver}
  tag: v#{ver.tr('-.', '_')}
  date: #{date.strftime("%Y-%m-%d")}
  post: /en/news/#{date.strftime("%Y/%m/%d")}/ruby-#{ver.tr('.', '-')}-released/
  stats:
    files_changed: #{files_changed}
    insertions: #{insertions}
    deletions: #{deletions}
  url:
    gz:  https://cache.ruby-lang.org/pub/ruby/#{xy}/ruby-#{ver}.tar.gz
    zip: https://cache.ruby-lang.org/pub/ruby/#{xy}/ruby-#{ver}.zip
    xz:  https://cache.ruby-lang.org/pub/ruby/#{xy}/ruby-#{ver}.tar.xz
  size:
    gz:  #{ary.find{|x|x.gz? }.size}
    zip: #{ary.find{|x|x.zip?}.size}
    xz:  #{ary.find{|x|x.xz? }.size}
  sha1:
    gz:  #{ary.find{|x|x.gz? }.sha1}
    zip: #{ary.find{|x|x.zip?}.sha1}
    xz:  #{ary.find{|x|x.xz? }.sha1}
  sha256:
    gz:  #{ary.find{|x|x.gz? }.sha256}
    zip: #{ary.find{|x|x.zip?}.sha256}
    xz:  #{ary.find{|x|x.xz? }.sha256}
  sha512:
    gz:  #{ary.find{|x|x.gz? }.sha512}
    zip: #{ary.find{|x|x.zip?}.sha512}
    xz:  #{ary.find{|x|x.xz? }.sha512}
eom

    if data.include?("\n- version: #{ver}\n")
    elsif data.sub!(/\n# #{Regexp.escape(xy)} series\n/, "\\&\n#{entry}")
    else
      data.sub!(/^$/, "\n# #{xy} series\n\n#{entry}")
    end
    File.write(File.join(wwwdir, filename), data)
  end
end

# Confirm current directory is www.ruby-lang.org's working directory
def confirm_w_r_l_o_wd
  File.foreach('.git/config') do |line|
    return true if line.include?('git@github.com:ruby/www.ruby-lang.org.git')
  end
  abort "Run this script in www.ruby-lang.org's working directory"
end

def main
  if ARGV.size != 1
    abort "usage: #$1 <version>"
  end
  confirm_w_r_l_o_wd
  version = ARGV.shift
  Tarball.parse(Dir.pwd, version)
end

main
