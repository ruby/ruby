#!./miniruby

load "./rbconfig.rb"
include Config

$:.unshift File.join(CONFIG["srcdir"], "lib")
require 'fileutils'
require 'shellwords'

File.umask(0)

while arg = ARGV.shift
  case arg
  when /^--make-flags=(.*)/
    Shellwords.shellwords($1).grep(/^-[^-]*n/) {break $dryrun = true}
  when "-n"
    $dryrun = true
  when /^-/
  else
    destdir ||= arg
  end
end
destdir ||= ''

include FileUtils::Verbose
include FileUtils::NoWrite if $dryrun
@fileutils_output = STDOUT
@fileutils_label = ''
alias makelink ln_sf

exeext = CONFIG["EXEEXT"]

ruby_install_name = CONFIG["ruby_install_name"]
rubyw_install_name = CONFIG["rubyw_install_name"]

version = CONFIG["ruby_version"]
bindir = destdir+CONFIG["bindir"]
libdir = destdir+CONFIG["libdir"]
rubylibdir = destdir+CONFIG["rubylibdir"]
archlibdir = destdir+CONFIG["archdir"]
sitelibdir = destdir+CONFIG["sitelibdir"]
sitearchlibdir = destdir+CONFIG["sitearchdir"]
mandir = File.join(destdir+CONFIG["mandir"], "man1")
configure_args = Shellwords.shellwords(CONFIG["configure_args"])
enable_shared = CONFIG["ENABLE_SHARED"] == 'yes'
dll = CONFIG["LIBRUBY_SO"]
lib = CONFIG["LIBRUBY"]
arc = CONFIG["LIBRUBY_A"]

makedirs [bindir, libdir, rubylibdir, archlibdir, sitelibdir, sitearchlibdir, mandir]

install ruby_install_name+exeext, File.join(bindir, ruby_install_name+exeext), 0755
if rubyw_install_name and !rubyw_install_name.empty?
  install rubyw_install_name+exeext, bindir, 0755
end
install dll, bindir, 0755 if enable_shared and dll != lib
install lib, libdir, 0555 unless lib == arc
install arc, libdir, 0644
install "config.h", archlibdir, 0644
install "rbconfig.rb", archlibdir, 0644
if CONFIG["ARCHFILE"]
  for file in CONFIG["ARCHFILE"].split
    install file, archlibdir, 0644
  end
end

if dll == lib and dll != arc
  for link in CONFIG["LIBRUBY_ALIASES"].split
    makelink(dll, File.join(libdir, link))
  end
end

Dir.chdir CONFIG["srcdir"]

for src in Dir["bin/*"]
  next unless File.file?(src)
  next if /\/[.#]|(\.(old|bak|orig|rej|diff|patch|core)|~|\/core)$/i =~ src

  name = ruby_install_name.sub(/ruby/, File.basename(src))
  dest = File.join(bindir, name)

  install src, dest, 0755

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
  } unless $dryrun
end

Dir.glob("lib/**/*{.rb,help-message}") do |f|
  dir = File.dirname(f).sub!(/\Alib/, rubylibdir) || rubylibdir
  makedirs dir unless File.directory? dir
  install f, dir, 0644
end

for f in Dir["*.h"]
  install f, archlibdir, 0644
end
if RUBY_PLATFORM =~ /mswin32|mingw|bccwin32/
  makedirs File.join(archlibdir, "win32")
  install "win32/win32.h", File.join(archlibdir, "win32"), 0644
end

install "ruby.1", File.join(mandir, ruby_install_name+".1"), 0644

# vi:set sw=2:
