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
bindir = destdir+CONFIG["bindir"]
libdir = destdir+CONFIG["libdir"]
pkglibdir = libdir + "/" + ruby_install_name
archdir = pkglibdir + "/" + CONFIG["arch"]
mandir = destdir+CONFIG["mandir"] + "/man1"
wdir = Dir.getwd

File.makedirs bindir, true
File.install ruby_install_name+binsuffix,
  "#{bindir}/#{ruby_install_name}#{binsuffix}", 0755, true
for dll in Dir['*.dll']
  File.install dll, "#{bindir}/#{dll}", 0755, true
end
File.makedirs libdir, TRUE
for lib in ["libruby.so", "libruby.so.LIB"]
  if File.exist? lib
    File.install lib, libdir, 0644, true
  end
end
File.makedirs pkglibdir, true
File.makedirs archdir, true
Dir.chdir "ext"
system "../miniruby#{binsuffix} extmk.rb install #{destdir}"
Dir.chdir CONFIG["srcdir"]
for f in Dir["lib/*.rb"]
  File.install f, pkglibdir, 0644, true
end

for f in Dir["*.h"]
  File.install f, archdir, 0644, true
end
File.install "#{wdir}/lib#{ruby_install_name}.a", archdir, 0644, true

File.makedirs mandir, true
File.install "ruby.1", mandir, 0644, true
Dir.chdir wdir
File.install "config.h", archdir, 0644, true
File.install "rbconfig.rb", archdir, 0644, true
# vi:set sw=2:
