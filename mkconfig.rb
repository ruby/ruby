#!./miniruby

require File.dirname($0)+"/lib/ftools"

rbconfig_rb = ARGV[0] || 'rbconfig.rb'
File.makedirs(File.dirname(rbconfig_rb), true)

version = VERSION
config = open(rbconfig_rb, "w")
$stdout.reopen(config)

fast = {'prefix'=>TRUE, 'INSTALL'=>TRUE, 'binsuffix'=>TRUE}
print %[
module Config

  VERSION == "#{version}" or
    raise "ruby lib version (#{version}) doesn't match executable version (\#{VERSION})"

# This file was created by configrb when ruby was built. Any changes
# made to this file will be lost the next time ruby is built.
]

print "  CONFIG = {}\n"
v_fast = []
v_others = []
File.foreach "config.status" do |$_|
  next if /^#/
  if /^s%@program_transform_name@%s,(.*)%g$/
    ptn = $1.sub(/\$\$/, '$').split(/,/)
    v_fast << "  CONFIG[\"ruby_install_name\"] = \"" + "ruby".sub(ptn[0],ptn[1]) + "\"\n"
  elsif /^s%@(\w+)@%(.*)%g/
    name = $1
    val = $2 || ""
    next if name =~ /^(INSTALL|DEFS|configure_input|srcdir|top_srcdir)$/
    v = "  CONFIG[\"" + name + "\"] = " +
      val.sub(/^\s*(.*)\s*$/, '"\1"').gsub(/\$\{?([^}]*)\}?/) {
      "\#{CONFIG[\\\"#{$1}\\\"]}"
    } + "\n"
    if fast[name]
      v_fast << v
    else
      v_others << v
    end
    if /DEFS/
      val.split(/\s*-D/).each do |i|
	if i =~ /(.*)=(\\")?([^\\]*)(\\")?/
	  key, val = $1, $3
	  if val == '1'
	    val = "TRUE"
	  else
	    val.sub! /^\s*(.*)\s*$/, '"\1"'
	  end
	  print "  CONFIG[\"#{key}\"] = #{val}\n"
	end
      end
    end
  elsif /^ac_given_srcdir=(.*)/
    path = $1
    cwd = Dir.pwd
    begin
      Dir.chdir path
      v_fast << "  CONFIG[\"srcdir\"] = \"" + Dir.pwd + "\"\n"
    ensure
      Dir.chdir cwd
    end
  elsif /^ac_given_INSTALL=(.*)/
    v_fast << "  CONFIG[\"INSTALL\"] = " + $1 + "\n"
  end
#  break if /^CEOF/
end

print v_fast, v_others
Dir.chdir File.dirname($0)
print "  CONFIG[\"compile_dir\"] = \"#{Dir.pwd}\"\n"
print "end\n"
config.close
# vi:set sw=2:
