#!./miniruby
# -*- coding: us-ascii -*-

require './rbconfig'
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

module Mswin
  def ln_safe(src, dest, *opt)
    cmd = ["mklink", dest.tr("/", "\\"), src.tr("/", "\\")]
    cmd[1, 0] = opt
    return if system("cmd", "/c", *cmd)
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

if /mingw|mswin/ =~ (CROSS_COMPILING || RUBY_PLATFORM)
  extend Mswin
end

def clean_path(path)
  path = "#{path}/".gsub(/(\A|\/)(?:\.\/)+/, '\1').tr_s('/', '/')
  nil while path.sub!(/[^\/]+\/\.\.\//, '')
  path
end

def relative_path_from(path, base)
  path = clean_path(path)
  base = clean_path(base)
  path, base = [path, base].map{|s|s.split("/")}
  until path.empty? or base.empty? or path[0] != base[0]
      path.shift
      base.shift
  end
  path, base = [path, base].map{|s|s.join("/")}
  if /(\A|\/)\.\.\// =~ base
    File.expand_path(path)
  else
    base.gsub!(/[^\/]+/, '..')
    File.join(base, path)
  end
end

def ln_relative(src, dest)
  return if File.identical?(src, dest)
  parent = File.dirname(dest)
  File.directory?(parent) or mkdir_p(parent)
  ln_safe(relative_path_from(src, parent), dest)
end

def ln_dir_relative(src, dest)
  return if File.identical?(src, dest)
  parent = File.dirname(dest)
  File.directory?(parent) or mkdir_p(parent)
  ln_dir_safe(relative_path_from(src, parent), dest)
end

config = RbConfig::MAKEFILE_CONFIG.merge("prefix" => ".", "exec_prefix" => ".")
config.each_value {|s| RbConfig.expand(s, config)}
srcdir = config["srcdir"] ||= File.dirname(__FILE__)
top_srcdir = config["top_srcdir"] ||= File.dirname(srcdir)
extout = ARGV[0] || config["EXTOUT"]
version = config["ruby_version"]
arch = config["arch"]
bindir = config["bindir"]
libdirname = config["libdirname"]
libdir = config[libdirname || "libdir"]
vendordir = config["vendordir"]
rubylibdir = config["rubylibdir"]
rubyarchdir = config["rubyarchdir"]
archdir = "#{extout}/#{arch}"
rubylibs = [vendordir, rubylibdir, rubyarchdir]
[bindir, libdir, archdir].uniq.each do |dir|
  File.directory?(dir) or mkdir_p(dir)
end

exeext = config["EXEEXT"]
ruby_install_name = config["ruby_install_name"]
rubyw_install_name = config["rubyw_install_name"]
goruby_install_name = "go" + ruby_install_name
[ruby_install_name, rubyw_install_name, goruby_install_name].map do |ruby|
  ruby += exeext
  if ruby and !ruby.empty?
    ln_relative(ruby, "#{bindir}/#{ruby}")
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
