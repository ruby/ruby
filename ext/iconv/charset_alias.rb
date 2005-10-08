#! /usr/bin/ruby
# :stopdoc:
require 'rbconfig'
require 'optparse'

# http://www.ctan.org/tex-archive/macros/texinfo/texinfo/intl/config.charset
# Fri, 30 May 2003 00:09:00 GMT'

OS = Config::CONFIG["target_os"]
SHELL = Config::CONFIG['SHELL']

class Hash::Ordered < Hash
  def [](key)
    val = super and val.last
  end
  def []=(key, val)
    ary = fetch(key) {return super(key, [self.size, key, val])} and
      ary.last = val
  end
  def each
    values.sort.each {|i, key, val| yield key, val}
  end
end

def charset_alias(config_charset, mapfile, target = OS)
  map = Hash::Ordered.new
  comments = []
  match = false
  open(config_charset) do |input|
    input.find {|line| /^case "\$os" in/ =~ line} or return
    input.find {|line|
      /^\s*([-\w\*]+(?:\s*\|\s*[-\w\*]+)*)(?=\))/ =~ line and
      $&.split('|').any? {|pattern| File.fnmatch?(pattern.strip, target)}
    } or return
    input.find do |line|
      case line
      when /^\s*echo "(?:\$\w+\.)?([-\w*]+)\s+([-\w]+)"/
        sys, can = $1, $2
        can.downcase!
        map[can] = sys
        false
      when /^\s*;;/
        true
      else
        false
      end
    end
  end
  case target
  when /linux|-gnu/
    map.delete('ascii')
  when /cygwin/
    # get rid of tilde/yen problem.
    map['shift_jis'] = 'cp932'
  end
  writer = proc do |f|
    f.puts("require 'iconv.so'")
    f.puts
    f.puts(comments)
    f.puts("class Iconv")
    map.each {|can, sys| f.puts("  charset_map['#{can}'.freeze] = '#{sys}'.freeze")}
    f.puts("end")
  end
  if mapfile
    open(mapfile, "w", &writer)
  else
    writer[STDOUT]
  end
end

target = OS
opt = nil
ARGV.options do |opt|
  opt.banner << " config.status map.rb"
  opt.on("--target OS") {|t| target = t}
  opt.parse! and (1..2) === ARGV.size
end or abort opt.to_s
charset_alias(ARGV[0], ARGV[1], target)
