#! /usr/bin/ruby
# :stopdoc:
require 'rbconfig'

# http://www.ctan.org/tex-archive/macros/texinfo/texinfo/intl/config.charset
# Fri, 30 May 2003 00:09:00 GMT'

OS = Config::CONFIG["target"]
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
  IO.foreach("|#{SHELL} #{config_charset} #{target}") do |list|
    next comments << list if /^\#/ =~ list
    next unless /^(\S+)\s+(\S+)$/ =~ list
    sys, can = $1, $2
    can.downcase!
    map[can] = sys
  end
  case target
  when /linux|-gnu/
    map.delete('ascii')
  when /cygwin/
    # get rid of tilde/yen problem.
    map['shift_jis'] = 'cp932'
  end
  open(mapfile, "w") do |f|
    f.puts("require 'iconv.so'")
    f.puts
    f.puts(comments)
    f.puts("class Iconv")
    map.each {|can, sys| f.puts("  charset_map['#{can}'.freeze] = '#{sys}'.freeze")}
    f.puts("end")
  end
end

(2..3) === ARGV.size or abort "usage: #$0 config.status map.rb [target]"
charset_alias(*ARGV)
