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

File.makedirs "#{destdir}#{bindir}", true
File.install "ruby#{binsuffix}",
  "#{destdir}#{bindir}/#{ruby_install_name}#{binsuffix}", 0755, true
for dll in Dir['*.dll']
  File.install dll, "#{destdir}#{bindir}/#{dll}", 0755, true
end
File.makedirs "#{destdir}#{libdir}", true
for lib in ["libruby.so.LIB", CONFIG["LIBRUBY_SO"]]
  if File.exist? lib
    File.install lib, "#{destdir}#{libdir}", 0644, true
  end
end
pwd = Dir.pwd
Dir.chdir libdir
if File.exist? CONFIG["LIBRUBY_SO"]
  for link in CONFIG["LIBRUBY_ALIASES"].split
    if File.exist? link
       File.delete link
    end
    File.symlink CONFIG["LIBRUBY_SO"], link
    print "link #{CONFIG['LIBRUBY_SO']} -> #{link}\n"
  end
end
Dir.chdir pwd
File.makedirs "#{destdir}#{pkglibdir}", true
File.makedirs "#{destdir}#{archdir}", true
Dir.chdir "ext"
system "../miniruby#{binsuffix} extmk.rb install #{destdir}"
Dir.chdir CONFIG["srcdir"]
for f in Dir["lib/*.rb"]
  File.install f, "#{destdir}#{pkglibdir}", 0644, true
end

File.makedirs(archdir,true)
for f in Dir["*.h"]
  File.install f, "#{destdir}#{archdir}", 0644, true
end
File.install CONFIG['LIBRUBY_A'], "#{destdir}#{archdir}", 0644, true

File.makedirs "#{destdir}#{mandir}", true
File.install "ruby.1", "#{destdir}#{mandir}", 0644, true
Dir.chdir wdir
File.install "config.h", "#{destdir}#{archdir}", 0644, true
File.install "rbconfig.rb", "#{destdir}#{archdir}", 0644, true
# vi:set sw=2:
