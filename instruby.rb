#!./miniruby

load "./rbconfig.rb"
include Config

File.umask(0)

$:.unshift CONFIG["srcdir"]+"/lib"
require "ftools"
require "find"
require "getopts"
require "tempfile"

getopts(nil, "mantype:doc")
mantype = $OPT["mantype"]
destdir = ARGV[0] || ''

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
mandir = destdir+CONFIG["mandir"] + "/man"
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
      File.install lib, libdir, 0755, true
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

for src in Dir["bin/*"]
  next unless File.file?(src)
  next if /\/[.#]|(\.(old|bak|orig|rej|diff|patch|core)|~|\/core)$/i =~ src

  name = ruby_install_name.sub(/ruby/, File.basename(src))
  dest = File.join(bindir, name)

  File.install src, dest, 0755, true

  open(dest, "r+") { |f|
    shebang = f.gets.sub(/ruby/, ruby_install_name)
    body = f.read

    f.rewind
    f.print shebang, body
    f.truncate(f.pos)
    f.close

    if RUBY_PLATFORM =~ /mswin32|mingw|bccwin32/
      open(dest + ".bat", "w") { |b|
	b.print <<EOH, shebang, body, <<EOF
@echo off
if "%OS%" == "Windows_NT" goto WinNT
ruby -Sx "%0" %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofruby
:WinNT
ruby -Sx "%~nx0" %*
goto endofruby
EOH
__END__
:endofruby
EOF
      }
    end
  }
end

Find.find("lib") do |f|
  next unless /\.rb$/ =~ f || /help-message$/ =~ f
  dir = rubylibdir+"/"+File.dirname(f[4..-1])
  File.makedirs dir, true unless File.directory? dir
  File.install f, dir, 0644, true
end

Dir.glob("*.h") do |f|
  File.install f, archlibdir, 0644, true
end

if RUBY_PLATFORM =~ /mswin32|mingw/
  File.makedirs archlibdir + "/win32", true
  File.install "win32/win32.h", archlibdir + "/win32", 0644, true
end
File.install wdir+'/'+CONFIG['LIBRUBY_A'], archlibdir, 0644, true

Dir.glob("*.[1-9]") do |mdoc|
  next unless open(mdoc){|fh| fh.read(1) == '.'}

  section = mdoc[-1,1]

  mandestdir = mandir + section
  destfile = File.join(mandestdir, mdoc.sub(/ruby/, ruby_install_name))

  File.makedirs mandestdir, true

  if mantype == "doc"
    File.install mdoc, destfile, 0644, true
  else
    require 'mdoc2man.rb'

    w = Tempfile.open(mdoc)

    open(mdoc) { |r|
      Mdoc2Man.mdoc2man(r, w)
    }

    w.close

    File.install w.path, destfile, 0644, true
  end
end

Dir.chdir wdir
File.install "config.h", archlibdir, 0644, true
File.install "rbconfig.rb", archlibdir, 0644, true
# vi:set sw=2:
