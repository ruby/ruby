#!./miniruby -I.

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
bindir = CONFIG["bindir"]
libdir = CONFIG["libdir"] + "/" + ruby_install_name
archdir = libdir+"/"+CONFIG["arch"]
mandir = CONFIG["mandir"] + "/man1"
wdir = Dir.getwd

File.makedirs bindir, TRUE
File.install "ruby#{binsuffix}",
  "#{bindir}/#{ruby_install_name}#{binsuffix}", 0755, TRUE
for dll in Dir['*.dll']
  File.install dll, "#{bindir}/#{dll}", 0755, TRUE
end
File.makedirs "#{libdir}", TRUE
for lib in ["libruby.so", "libruby.so.LIB"]
  if File.exist? lib
    File.install lib, "#{libdir}", 0644, TRUE
  end
end
File.makedirs libdir, TRUE
Dir.chdir "ext"
system "../miniruby#{binsuffix} extmk.rb install"
Dir.chdir CONFIG["srcdir"]
for f in Dir["lib/*.rb"]
  File.install f, "#{libdir}", 0644, TRUE
end
for f in Dir["*.h"]
  File.install f, "#{archdir}", 0644, TRUE
end
File.makedirs mandir, TRUE
File.install "ruby.1", "#{mandir}", 0644, TRUE
Dir.chdir wdir
File.install "config.h", "#{archdir}", 0644, TRUE
File.install "rbconfig.rb", "#{archdir}", 0644, TRUE
# vi:set sw=2:
