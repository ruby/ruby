#!./miniruby -s

# avoid warnings with -d.
$install_name ||= nil
$so_name ||= nil

srcdir = File.dirname(__FILE__)
$:.replace [srcdir+"/lib"] unless defined?(CROSS_COMPILING)
$:.unshift(".")

require "fileutils"
mkconfig = File.basename($0)

rbconfig_rb = ARGV[0] || 'rbconfig.rb'
unless File.directory?(dir = File.dirname(rbconfig_rb))
  FileUtils.makedirs(dir, :verbose => true)
end

version = RUBY_VERSION
def (config = "").write(arg)
  concat(arg.to_s)
end
$stdout = config

fast = {'prefix'=>TRUE, 'ruby_install_name'=>TRUE, 'INSTALL'=>TRUE, 'EXEEXT'=>TRUE}
print %[
# This file was created by #{mkconfig} when ruby was built.  Any
# changes made to this file will be lost the next time ruby is built.

module Config
  RUBY_VERSION == "#{version}" or
    raise "ruby lib version (#{version}) doesn't match executable version (\#{RUBY_VERSION})"

]

v_fast = []
v_others = []
vars = {}
has_version = false
has_patchlevel = false
continued_name = nil
continued_line = nil
File.foreach "config.status" do |line|
  next if /^#/ =~ line
  name = nil
  case line
  when /^s([%,])@(\w+)@\1(?:\|\#_!!_\#\|)?(.*)\1/
    name = $2
    val = $3.gsub(/\\(?=,)/, '')
  when /^S\["(\w+)"\]\s*=\s*"(.*)"\s*(\\)?$/
    name = $1
    val = $2
    if $3
      continued_line = []
      continued_line << val
      continued_name = name
      next
    end
  when /^"(.*)"\s*(\\)?$/
    if continued_line
      continued_line <<  $1
      next if $2
      val = continued_line.join("")
      name = continued_name
      continued_line = nil
    end
  when /^(?:ac_given_)?INSTALL=(.*)/
    v_fast << "  CONFIG[\"INSTALL\"] = " + $1 + "\n"
  end

  if name
    next if /^(?:ac_.*|configure_input|(?:top_)?srcdir|\w+OBJS)$/ =~ name
    next if /^\$\(ac_\w+\)$/ =~ val
    next if /^\$\{ac_\w+\}$/ =~ val
    next if /^\$ac_\w+$/ =~ val
    next if $install_name and /^RUBY_INSTALL_NAME$/ =~ name
    next if $so_name and /^RUBY_SO_NAME$/ =~  name
    next if /^(?:X|(?:MINI|RUN)RUBY$)/ =~ name
    if /^program_transform_name$/ =~ name and /^s(\\?.)(.*)\1$/ =~ val
      next if $install_name
      sep = %r"#{Regexp.quote($1)}"
      ptn = $2.sub(/\$\$/, '$').split(sep, 2)
      name = "ruby_install_name"
      val = "ruby".sub(/#{ptn[0]}/, ptn[1])
    end
    val.gsub!(/ +(?!-)/, "=") if name == "configure_args" && /mswin32/ =~ RUBY_PLATFORM
    val = val.gsub(/\$(?:\$|\{?(\w+)\}?)/) {$1 ? "$(#{$1})" : $&}.dump
    if /^prefix$/ =~ name
      val = "(TOPDIR || DESTDIR + #{val})"
    end
    v = "  CONFIG[\"#{name}\"] #{vars[name] ? '<< "\n"' : '='} #{val}\n"
    vars[name] = true
    if fast[name]
      v_fast << v
    else
      v_others << v
    end
    case name
    when "MAJOR"
      has_version = true
    when "PATCHLEVEL"
      has_patchlevel = true
    end
  end
#  break if /^CEOF/
end

drive = File::PATH_SEPARATOR == ';'

prefix = '/lib/ruby/' + RUBY_VERSION.sub(/\.\d+$/, '') + '/' + RUBY_PLATFORM
print "  TOPDIR = File.dirname(__FILE__).chomp!(#{prefix.dump})\n"
print "  DESTDIR = ", (drive ? "TOPDIR && TOPDIR[/\\A[a-z]:/i] || " : ""), "'' unless defined? DESTDIR\n"
print "  CONFIG = {}\n"
print "  CONFIG[\"DESTDIR\"] = DESTDIR\n"

unless has_version
  RUBY_VERSION.scan(/(\d+)\.(\d+)\.(\d+)/) {
    print "  CONFIG[\"MAJOR\"] = \"" + $1 + "\"\n"
    print "  CONFIG[\"MINOR\"] = \"" + $2 + "\"\n"
    print "  CONFIG[\"TEENY\"] = \"" + $3 + "\"\n"
  }
end
unless has_patchlevel
  patchlevel = IO.foreach(File.join(srcdir, "version.h")) {|l|
    m = /^\s*#\s*define\s+RUBY_PATCHLEVEL\s+(\d+)/.match(l) and break m[1]
  }
  print "  CONFIG[\"PATCHLEVEL\"] = \"#{patchlevel}\"\n"
end

dest = drive ? /= \"(?!\$[\(\{])(?:[a-z]:)?/i : /= \"(?!\$[\(\{])/
v_others.collect! do |x|
  if /^\s*CONFIG\["(?!abs_|old)[a-z]+(?:_prefix|dir)"\]/ === x
    x.sub(dest, '= "$(DESTDIR)')
  else
    x
  end
end

if $install_name
  v_fast << "  CONFIG[\"ruby_install_name\"] = \"" + $install_name + "\"\n"
  v_fast << "  CONFIG[\"RUBY_INSTALL_NAME\"] = \"" + $install_name + "\"\n"
end
if $so_name
  v_fast << "  CONFIG[\"RUBY_SO_NAME\"] = \"" + $so_name + "\"\n"
end

print(*v_fast)
print(*v_others)
print <<EOS
  CONFIG["ruby_version"] = "$(MAJOR).$(MINOR)"
  CONFIG["rubylibdir"] = "$(libdir)/ruby/$(ruby_version)"
  CONFIG["archdir"] = "$(rubylibdir)/$(arch)"
  CONFIG["sitelibdir"] = "$(sitedir)/$(ruby_version)"
  CONFIG["sitearchdir"] = "$(sitelibdir)/$(sitearch)"
  CONFIG["vendorlibdir"] = "$(vendordir)/$(ruby_version)"
  CONFIG["vendorarchdir"] = "$(vendorlibdir)/$(sitearch)"
  CONFIG["topdir"] = File.dirname(__FILE__)
  MAKEFILE_CONFIG = {}
  CONFIG.each{|k,v| MAKEFILE_CONFIG[k] = v.dup}
  def Config::expand(val, config = CONFIG)
    val.gsub!(/\\$\\$|\\$\\(([^()]+)\\)|\\$\\{([^{}]+)\\}/) do |var|
      if !(v = $1 || $2)
	'$'
      elsif key = config[v = v[/\\A[^:]+(?=(?::(.*?)=(.*))?\\z)/]]
	pat, sub = $1, $2
	config[v] = false
	Config::expand(key, config)
	config[v] = key
	key = key.gsub(/\#{Regexp.quote(pat)}(?=\\s|\\z)/n) {sub} if pat
	key
      else
	var
      end
    end
    val
  end
  CONFIG.each_value do |val|
    Config::expand(val)
  end
end
RbConfig = Config # compatibility for ruby-1.9
CROSS_COMPILING = nil unless defined? CROSS_COMPILING
EOS

$stdout = STDOUT
mode = IO::RDWR|IO::CREAT
mode |= IO::BINARY if defined?(IO::BINARY)
open(rbconfig_rb, mode) do |f|
  if $timestamp and f.stat.size == config.size and f.read == config
    puts "#{rbconfig_rb} unchanged"
  else
    puts "#{rbconfig_rb} updated"
    f.rewind
    f.truncate(0)
    f.print(config)
  end
end
if String === $timestamp
  FileUtils.touch($timestamp)
end

# vi:set sw=2:
