#! /usr/bin/ruby
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
      ary << val
  end
  def sort
    values.sort.collect {|i, *rest| rest}
  end
  def each(&block)
    sort.each(&block)
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
#    map.delete('ascii')
  when /cygwin|os2-emx/
    # get rid of tilde/yen problem.
    map['shift_jis'] = 'cp932'
  end
  st = Hash.new(0)
  map = map.sort.collect do |can, *sys|
    if sys.grep(/^en_us(?=.|$)/i) {break true} == true
      noen = %r"^(?!en_us)\w+_\w+#{Regexp.new($')}$"i
      sys.reject! {|s| noen =~ s}
    end
    sys = sys.first
    st[sys] += 1
    [can, sys]
  end
  st.delete_if {|sys, i| i == 1}.empty?
  st.keys.each {|sys| st[sys] = nil}
  st.default = nil
  open(mapfile, "w") do |f|
    f.puts("require 'iconv.so'")
    f.puts
    f.puts(comments)
    f.puts("class Iconv")
    i = 0
    map.each do |can, sys|
      if s = st[sys]
        sys = s
      elsif st.key?(sys)
        sys = (st[sys] = "sys#{i+=1}") + " = '#{sys}'.freeze"
      else
        sys = "'#{sys}'.freeze"
      end
      f.puts("  charset_map['#{can}'.freeze] = #{sys}")
    end
    f.puts("end")
  end
end

(2..3) === ARGV.size or abort "usage: #$0 config.status map.rb [target]"
charset_alias(*ARGV)
