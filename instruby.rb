#!./miniruby

load "./rbconfig.rb"
include Config

File.umask(0)
destdir = ARGV[0] || ''

$:.unshift CONFIG["srcdir"]+"/lib"
require "ftools"
require "find"

exeext = CONFIG["EXEEXT"]
if ENV["prefix"]
  prefix = ENV["prefix"]
else
  prefix = CONFIG["prefix"]
end

ruby_install_name = CONFIG["ruby_install_name"]
version = "/"+CONFIG["MAJOR"]+"."+CONFIG["MINOR"]
arch = "/"+CONFIG["arch"]

bindir = destdir+CONFIG["bindir"]
libdir = destdir+CONFIG["libdir"]
rubylibdir = destdir+CONFIG["prefix"]+"/lib/ruby"+version
archlibdir = rubylibdir+arch
sitelibdir = destdir+CONFIG["sitedir"]+version
sitearchlibdir = sitelibdir+arch
mandir = destdir+CONFIG["mandir"] + "/man1"
wdir = Dir.getwd

File.makedirs bindir, true
File.install ruby_install_name+exeext,
  "#{bindir}/#{ruby_install_name}#{exeext}", 0755, true
rubyw = ruby_install_name.sub(/ruby/, '\&w')+exeext
if File.exist? rubyw
  File.install rubyw, "#{bindir}/#{rubyw}", 0755, true
end
for dll in Dir['*.dll']
  File.install dll, "#{bindir}/#{dll}", 0755, true
end
File.makedirs libdir, true
if CONFIG["LIBRUBY"] != CONFIG["LIBRUBY_A"]
  for lib in [CONFIG["LIBRUBY"]]
    if File.exist? lib
      File.install lib, libdir, 0555, true
    end
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
File.makedirs rubylibdir, true
File.makedirs archlibdir, true
File.makedirs sitelibdir, true
File.makedirs sitearchlibdir, true

if RUBY_PLATFORM =~ /-aix/
  File.install "ruby.imp", archlibdir, 0644, true
end

Dir.chdir "ext"
if defined? CROSS_COMPILING
  system "#{CONFIG['MINIRUBY']} extmk.rb install #{destdir}"
else
  system "../miniruby#{exeext} extmk.rb install #{destdir}"
end
Dir.chdir CONFIG["srcdir"]

File.install "sample/irb.rb", "#{bindir}/irb", 0755, true

Find.find("lib") do |f|
  next unless /\.rb$/ =~ f || /help-message$/ =~ f
  dir = rubylibdir+"/"+File.dirname(f[4..-1])
  File.makedirs dir, true unless File.directory? dir
  File.install f, dir, 0644, true
end

for f in Dir["*.h"]
  File.install f, archlibdir, 0644, true
end
if RUBY_PLATFORM =~ /mswin32|mingw/
  File.makedirs archlibdir + "/win32", true
  File.install "win32/win32.h", archlibdir + "/win32", 0644, true
end
File.install wdir+'/'+CONFIG['LIBRUBY_A'], archlibdir, 0644, true

File.makedirs mandir, true
File.install "ruby.1", mandir+"/"+ruby_install_name+".1", 0644, true
Dir.chdir wdir
File.install "config.h", archlibdir, 0644, true
File.install "rbconfig.rb", archlibdir, 0644, true
# vi:set sw=2:
