#!./miniruby
require "rbconfig.rb"
include Config

$:.unshift CONFIG["srcdir"]+"/lib"
require "ftools"

binsuffix = CONFIG["binsuffix"]
if ENV["prefix"]
  prefix = ENV["prefix"]
else
  prefix = CONFIG["prefix"]
end
ruby_install_name = CONFIG["ruby_install_name"]
bindir = prefix + "/bin"
libdir = prefix + "/lib/" + ruby_install_name
archdir = libdir+"/"+CONFIG["arch"]
mandir = CONFIG["mandir"] + "/man1"

File.install "ruby#{binsuffix}",
  "#{bindir}/#{ruby_install_name}#{binsuffix}", 0755, TRUE
File.makedirs libdir, TRUE
Dir.chdir "ext"
system "../miniruby#{binsuffix} extmk.rb install"
Dir.chdir CONFIG["srcdir"]
IO.foreach 'MANIFEST' do |$_|
  $_.chop!
  if /^lib/
    File.install $_, libdir, 0644, TRUE
  elsif /^[a-z]+\.h$/
    File.install $_, archdir, 0644, TRUE
  end
  File.install "config.h", archdir, 0644, TRUE
end
File.install "rbconfig.rb", archdir, 0644, TRUE
File.makedirs mandir, TRUE
File.install "ruby.1", mandir, 0644, TRUE
# vi:set sw=2:
