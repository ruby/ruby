#!./miniruby -s

require File.dirname($0)+"/lib/ftools"

rbconfig_rb = ARGV[0] || 'rbconfig.rb'
srcdir = $srcdir if $srcdir
File.makedirs(File.dirname(rbconfig_rb), true)

version = RUBY_VERSION
rbconfig_rb_tmp = rbconfig_rb + '.tmp'
config = open(rbconfig_rb_tmp, "w")
$orgout = $stdout.dup
$stdout.reopen(config)

fast = {'prefix'=>TRUE, 'ruby_install_name'=>TRUE, 'INSTALL'=>TRUE, 'EXEEXT'=>TRUE}
print %[
module Config

  RUBY_VERSION == "#{version}" or
    raise "ruby lib version (#{version}) doesn't match executable version (\#{RUBY_VERSION})"

# This file was created by configrb when ruby was built. Any changes
# made to this file will be lost the next time ruby is built.
]

print "  DESTDIR = '' if not defined? DESTDIR\n  CONFIG = {}\n"
v_fast = []
v_others = []
has_srcdir = false
has_version = false
File.foreach "config.status" do |line|
  next if /^#/ =~ line
  if /^s[%,]@program_transform_name@[%,]s,(.*)/ =~ line
    next if $install_name
    ptn = $1.sub(/\$\$/, '$').split(/,/)	#'
    v_fast << "  CONFIG[\"ruby_install_name\"] = \"" + "ruby".sub(/#{ptn[0]}/,ptn[1]) + "\"\n"
  elsif /^s[%,]@(\w+)@[%,](.*)[%,]/ =~ line
    name = $1
    val = $2 || ""
    next if /^(INSTALL|DEFS|configure_input|srcdir|top_srcdir)$/ =~ name
    next if $install_name and /^RUBY_INSTALL_NAME$/ =~ name
    next if $so_name and /^RUBY_SO_NAME$/ =~  name
    v = "  CONFIG[\"" + name + "\"] = " +
      val.strip.gsub(/\$\{?(\w+)\}?/) {"$(#{$1})"}.dump + "\n"
    if fast[name]
      v_fast << v
    else
      v_others << v
    end
    has_version = true if name == "MAJOR"
  elsif /^(?:ac_given_)?srcdir=(.*)/ =~ line
    v_fast << "  CONFIG[\"srcdir\"] = \"" + File.expand_path($1) + "\"\n"
    has_srcdir = true
  elsif /^ac_given_INSTALL=(.*)/ =~ line
    v_fast << "  CONFIG[\"INSTALL\"] = " + $1 + "\n"
  end
#  break if /^CEOF/
end

if not has_srcdir
  v_fast << "  CONFIG[\"srcdir\"] = \"" + File.expand_path(srcdir || '.') + "\"\n"
end

if not has_version
  RUBY_VERSION.scan(/(\d+)\.(\d+)\.(\d+)/) {
    print "  CONFIG[\"MAJOR\"] = \"" + $1 + "\"\n"
    print "  CONFIG[\"MINOR\"] = \"" + $2 + "\"\n"
    print "  CONFIG[\"TEENY\"] = \"" + $3 + "\"\n"
  }
end

v_fast.collect! do |x|
  if /"prefix"/ === x
    prefix = Regexp.quote('/lib/ruby/' + RUBY_VERSION.sub(/\.\d+$/, '') + '/' + RUBY_PLATFORM)
    puts "  TOPDIR = File.dirname(__FILE__).sub!(%r'#{prefix}\\Z', '')"
    x.sub(/= (.*)/, '= (TOPDIR || DESTDIR + \1)')
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

print v_fast, v_others
print <<EOS
  CONFIG["ruby_version"] = "$(MAJOR).$(MINOR)"
  CONFIG["rubylibdir"] = "$(libdir)/ruby/$(ruby_version)"
  CONFIG["archdir"] = "$(rubylibdir)/$(arch)"
  CONFIG["sitelibdir"] = "$(sitedir)/$(ruby_version)"
  CONFIG["sitearchdir"] = "$(sitelibdir)/$(sitearch)"
  CONFIG["compile_dir"] = "#{Dir.pwd}"
  MAKEFILE_CONFIG = {}
  CONFIG.each{|k,v| MAKEFILE_CONFIG[k] = v.dup}
  def Config::expand(val)
    val.gsub!(/\\$\\(([^()]+)\\)|\\$\\{([^{}]+)\\}/) do |var|
      if key = CONFIG[$1 || $2]
        Config::expand(key)
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
EOS
$stdout.flush
$stdout.reopen($orgout)
config.close
File.rename(rbconfig_rb_tmp, rbconfig_rb)

# vi:set sw=2:
