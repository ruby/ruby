#!./miniruby
# -*- coding: us-ascii -*-

require 'fileutils'

case ARGV[0]
when "-n"
  ARGV.shift
  include FileUtils::DryRun
when "-v"
  ARGV.shift
  include FileUtils::Verbose
else
  include FileUtils
end

def relative_from(path, base)
  dir = File.join(path, "")
  if File.expand_path(dir) == File.expand_path(dir, base)
    path
  else
    File.join(base, path)
  end
end

module Mswin
  def ln_safe(src, dest, *opt)
    cmd = ["mklink", dest.tr("/", "\\"), src.tr("/", "\\")]
    cmd[1, 0] = opt
    # TODO: use RUNAS or something
    puts cmd.join(" ")
  end

  def ln_dir_safe(src, dest)
    ln_safe(src, dest, "/d")
  end
end

def ln_safe(src, dest)
  link = File.readlink(dest) rescue nil
  return if link == src
  ln_sf(src, dest)
end

alias ln_dir_safe ln_safe

if /mingw|mswin/ =~ CROSS_COMPILING
  extend Mswin
end

config = RbConfig::CONFIG
srcdir = config["srcdir"] ||= File.dirname(__FILE__)
top_srcdir = config["top_srcdir"] ||= File.dirname(srcdir)
extout = ARGV[0] || config["EXTOUT"]
version = config["ruby_version"]
arch = config["arch"]
bindir = File.basename(config["bindir"])
libdir = File.basename(config["libdir"])
archdir = File.join(extout, arch)
[bindir, libdir, archdir].each do |dir|
  File.directory?(dir) or mkdir_p(dir)
end

exeext = config["EXEEXT"]
ruby_install_name = config["ruby_install_name"]
rubyw_install_name = config["rubyw_install_name"]
goruby_install_name = "go" + ruby_install_name
[ruby_install_name, rubyw_install_name, goruby_install_name].map do |ruby|
  ruby += exeext
  if ruby and !ruby.empty?
    ln_safe("../#{ruby}", "#{bindir}/#{ruby}")
  end
end
libruby = config.values_at("LIBRUBY_A", "LIBRUBY_SO")
libruby.concat(config["LIBRUBY_ALIASES"].split)
libruby.each {|lib|ln_safe("../#{lib}", "#{libdir}/#{lib}")}
if File.expand_path(extout) == extout
  ln_dir_safe(extout, "#{libdir}/ruby")
else
  ln_dir_safe(File.join("..", extout), "#{libdir}/ruby")
  cur = "#{extout}/".gsub(/(\A|\/)(?:\.\/)+/, '\1').tr_s('/', '/')
  nil while cur.sub!(/[^\/]+\/\.\.\//, '')
  if /(\A|\/)\.\.\// =~ cur
    cur = nil
  else
    cur.gsub!(/[^\/]+/, '..')
  end
end
if cur
  ln_safe(File.join("..", cur, "rbconfig.rb"), File.join(archdir, "rbconfig.rb"))
else
  ln_safe(File.expand_path("rbconfig.rb"), File.join(archdir, "rbconfig.rb"))
end
ln_dir_safe("common", File.join(extout, version))
ln_dir_safe(File.join("..", arch), File.join(extout, "common", arch))
ln_dir_safe(relative_from(File.join(top_srcdir, "lib"), ".."), File.join(extout, "vendor_ruby"))
