#!./miniruby -I.

require "rbconfig.rb"
include Config

destdir = ARGV[0] || ''

$:.unshift CONFIG["srcdir"]+"/lib"
require "ftools"

binsuffix = CONFIG["binsuffix"]
if ENV["prefix"]
  prefix = ENV["prefix"]
else
  prefix = CONFIG["prefix"]
end
ruby_install_name = CONFIG["ruby_install_name"]
bindir = CONFIG["bindir"]
libdir = CONFIG["libdir"]
pkglibdir = libdir + "/" + ruby_install_name
archdir = pkglibdir + "/" + CONFIG["arch"]
mandir = CONFIG["mandir"] + "/man1"
wdir = Dir.getwd

File.makedirs "#{destdir}#{bindir}", TRUE
File.install "ruby#{binsuffix}",
  "#{destdir}#{bindir}/#{ruby_install_name}#{binsuffix}", 0755, TRUE
for dll in Dir['*.dll']
  File.install dll, "#{destdir}#{bindir}/#{dll}", 0755, TRUE
end
File.makedirs "#{destdir}#{libdir}", TRUE
for lib in ["libruby.so", "libruby.so.LIB"]
  if File.exist? lib
    File.install lib, "#{destdir}#{libdir}", 0644, TRUE
  end
end
File.makedirs "#{destdir}#{pkglibdir}", TRUE
File.makedirs "#{destdir}#{archdir}", TRUE
Dir.chdir "ext"
system "../miniruby#{binsuffix} extmk.rb install #{destdir}"
Dir.chdir CONFIG["srcdir"]
IO.foreach 'MANIFEST' do |$_|
  $_.chop!
  if /^lib/
    File.install $_, "#{destdir}#{pkglibdir}", 0644, TRUE
  elsif /^[a-z]+\.h$/
    File.install $_, "#{destdir}#{archdir}", 0644, TRUE
  end
end
File.makedirs "#{destdir}#{mandir}", TRUE
File.install "ruby.1", "#{destdir}#{mandir}", 0644, TRUE
Dir.chdir wdir
File.install "config.h", "#{destdir}#{archdir}", 0644, TRUE
File.install "rbconfig.rb", "#{destdir}#{archdir}", 0644, TRUE
# vi:set sw=2:
