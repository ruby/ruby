#!./miniruby
# -*- coding: us-ascii -*-

# Used by "make runnable" target, to make symbolic links from a build
# directory.

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

def clean_link(src, dest)
  begin
    link = File.readlink(dest)
  rescue
  else
    return if link == src
    File.unlink(dest)
  end
  yield src, dest
end

def ln_safe(src, dest)
  ln_sf(src, dest)
rescue Errno::ENOENT
  # Windows disallows to create broken symboic links, probably because
  # it is a kind of reparse points.
  raise if File.exist?(src)
end

alias ln_dir_safe ln_safe

case RUBY_PLATFORM
when /linux|darwin|solaris/
  def ln_exe(src, dest)
    ln(src, dest, force: true)
  end
else
  alias ln_exe ln_safe
end

if !File.respond_to?(:symlink) && /mingw|mswin/ =~ (CROSS_COMPILING || RUBY_PLATFORM)
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

def ln_relative(src, dest, executable = false)
  return if File.identical?(src, dest)
  parent = File.dirname(dest)
  File.directory?(parent) or mkdir_p(parent)
  return ln_exe(src, dest) if executable
  clean_link(relative_path_from(src, parent), dest) {|s, d| ln_safe(s, d)}
end

def ln_dir_relative(src, dest)
  return if File.identical?(src, dest)
  parent = File.dirname(dest)
  File.directory?(parent) or mkdir_p(parent)
  clean_link(relative_path_from(src, parent), dest) {|s, d| ln_dir_safe(s, d)}
end

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
[bindir, libdir, archdir].uniq.each do |dir|
  File.directory?(dir) or mkdir_p(dir)
end

exeext = config["EXEEXT"]
ruby_install_name = config["ruby_install_name"]
rubyw_install_name = config["rubyw_install_name"]
goruby_install_name = "go" + ruby_install_name
[ruby_install_name, rubyw_install_name, goruby_install_name].map do |ruby|
  if ruby and !ruby.empty?
    ruby += exeext
    ln_relative(ruby, "#{bindir}/#{ruby}", true)
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
