#!./miniruby -I.

require "rbconfig.rb"
include Config

destdir = ARGV[0] || ''

$:.unshift CONFIG["srcdir"]+"/lib"
require "ftools"
require "find"

binsuffix = CONFIG["binsuffix"]
if ENV["prefix"]
  prefix = ENV["prefix"]
else
  prefix = CONFIG["prefix"]
end
ruby_install_name = CONFIG["ruby_install_name"]
bindir = destdir+CONFIG["bindir"]
libdir = destdir+CONFIG["libdir"]
#pkglibdir = libdir + "/" + ruby_install_name+"/"+CONFIG["MAJOR"]+"."+CONFIG["MINOR"]
pkglibdir = libdir + "/ruby/"+CONFIG["MAJOR"]+"."+CONFIG["MINOR"]
archdir = pkglibdir + "/" + CONFIG["arch"]
mandir = destdir+CONFIG["mandir"] + "/man1"
wdir = Dir.getwd

File.makedirs bindir, true
File.install ruby_install_name+binsuffix,
  "#{bindir}/#{ruby_install_name}#{binsuffix}", 0755, true
for dll in Dir['*.dll']
  File.install dll, "#{bindir}/#{dll}", 0755, true
end
File.makedirs libdir, true
for lib in ["libruby.so.LIB", CONFIG["LIBRUBY_SO"]]
  if File.exist? lib
    File.install lib, libdir, 0555, true
  end
end
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
Dir.chdir wdir
File.makedirs pkglibdir, true
File.makedirs archdir, true
File.makedirs pkglibdir+"/site_ruby", true
File.makedirs pkglibdir+"/site_ruby/"+CONFIG["arch"], true

if RUBY_PLATFORM =~ /cygwin/ and File.exist? "import.h"
  File.install "import.h", archdir, 0644, true
end

if RUBY_PLATFORM =~ /-aix/
  File.install "ruby.imp", archdir, 0644, true
end

Dir.chdir "ext"
system "../miniruby#{binsuffix} extmk.rb install #{destdir}"
Dir.chdir CONFIG["srcdir"]

Find.find("lib") do |f|
  next unless /\.rb$/ =~ f
  dir = pkglibdir+"/"+File.dirname(f[4..-1])
  File.makedirs dir, true unless File.directory? dir
  File.install f, dir, 0644, true
end

for f in Dir["*.h"]
  File.install f, archdir, 0644, true
end
File.install wdir+'/'+CONFIG['LIBRUBY_A'], archdir, 0644, true

File.makedirs mandir, true
File.install "ruby.1", mandir, 0644, true
Dir.chdir wdir
File.install "config.h", archdir, 0644, true
File.install "rbconfig.rb", archdir, 0644, true
# vi:set sw=2:
