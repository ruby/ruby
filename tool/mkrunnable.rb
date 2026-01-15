#!./miniruby
# -*- coding: us-ascii -*-

# Used by "make runnable" target, to make symbolic links from a build
# directory.

require './rbconfig'
require 'fileutils'
require_relative 'lib/path'

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

include Path

config = RbConfig::MAKEFILE_CONFIG.merge("prefix" => ".", "exec_prefix" => ".")
config.each_value {|s| RbConfig.expand(s, config)}
srcdir = config["srcdir"] ||= File.dirname(__FILE__)
top_srcdir = config["top_srcdir"] ||= File.dirname(srcdir)
extout = ARGV[0] || config["EXTOUT"]
arch = config["arch"]
bindir = config["bindir"]
libdirname = config["libdirname"]
libdir = config[libdirname || "libdir"]
vendordir = config["vendordir"]
rubylibdir = config["rubylibdir"]
rubyarchdir = config["rubyarchdir"]
archdir = "#{extout}/#{arch}"
exedir = bindir
if libdirname == "archlibdir"
  exedir = exedir.sub(%r[/\K(?=[^/]+\z)]) {extout+"/"}
end
[exedir, libdir, archdir].uniq.each do |dir|
  File.directory?(dir) or mkdir_p(dir)
end
unless exedir == bindir
  ln_dir_relative(exedir, bindir)
end

exeext = config["EXEEXT"]
ruby_install_name = config["ruby_install_name"]
rubyw_install_name = config["rubyw_install_name"]
goruby_install_name = "go" + ruby_install_name
[ruby_install_name, rubyw_install_name, goruby_install_name].each do |ruby|
  if ruby and !ruby.empty?
    ruby += exeext
    ln_relative(ruby, "#{exedir}/#{ruby}", true)
  end
end
so = config["LIBRUBY_SO"]
libruby = [config["LIBRUBY_A"]]
if /\.dll\z/i =~ so
  ln_relative(so, "#{bindir}/#{so}")
else
  libruby << so
end
libruby.concat(config["LIBRUBY_ALIASES"].split)
libruby.each {|lib|ln_relative(lib, "#{libdir}/#{lib}")}
ln_dir_relative("#{extout}/common", rubylibdir)
rubyarchdir.sub!(rubylibdir, "#{extout}/common")
vendordir.sub!(rubylibdir, "#{extout}/common")
ln_dir_relative(archdir, rubyarchdir)
vendordir.sub!(rubyarchdir, archdir)
ln_dir_relative("#{top_srcdir}/lib", vendordir)
ln_relative("rbconfig.rb", "#{archdir}/rbconfig.rb")
