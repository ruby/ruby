#!./miniruby

require 'mkmf'

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

if /mingw|mswin/ =~ RUBY_PLATFORM
  extend Mswin
end

config = RbConfig::CONFIG
extout = ARGV[0] || config["EXTOUT"]
version = config["ruby_version"]
arch = config["arch"]
["bin", "lib"].each do |dir|
  File.directory?(dir) or mkdir_p(dir)
end

exeext = config["EXEEXT"]
ruby_install_name = config["ruby_install_name"]
rubyw_install_name = config["rubyw_install_name"]
goruby_install_name = "go" + ruby_install_name
[ruby_install_name, rubyw_install_name, goruby_install_name].map do |ruby|
  ruby += exeext
  if ruby and !ruby.empty?
    ln_safe("../#{ruby}", "bin/#{ruby}")
  end
end
libruby = config.values_at("LIBRUBY_A", "LIBRUBY_SO")
libruby.concat(config["LIBRUBY_ALIASES"].split)
libruby.each {|lib|ln_safe("../#{lib}", "lib/#{lib}")}
if File.expand_path(extout) == extout
  ln_dir_safe(extout, "lib/ruby")
else
  ln_dir_safe(File.join("..", extout), "lib/ruby")
  cur = "#{extout}/".gsub(/(\A|\/)(?:\.\/)+/, '\1').tr_s('/', '/')
  nil while cur.sub!(/[^\/]+\/\.\.\//, '')
  if /(\A|\/)\.\.\// =~ cur
    cur = nil
  else
    cur.gsub!(/[^\/]+/, '..')
  end
end
if cur
  ln_safe(File.join("..", cur, "rbconfig.rb"), File.join(extout, arch, "rbconfig.rb"))
else
  ln_safe(File.expand_path("rbconfig.rb"), File.join(extout, arch, "rbconfig.rb"))
end
ln_dir_safe("common", File.join(extout, version))
ln_dir_safe(File.join("..", arch), File.join(extout, "common", arch))
ln_dir_safe(relative_from(File.join(File.dirname(config["srcdir"]), "lib"), ".."), File.join(extout, "vendor_ruby"))
