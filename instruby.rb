#!./miniruby

load "./rbconfig.rb"
include Config

$:.unshift File.join(CONFIG["srcdir"], "lib")
require 'fileutils'
require 'shellwords'
require 'getopts'
require 'tempfile'

File.umask(0)

def parse_args()
  getopts('n', 'dest-dir:',
	  'make:', 'make-flags:', 'mflags:',
	  'mantype:doc')

  $dryrun = $OPT['n']
  $destdir = $OPT['dest-dir'] || ''
  $make = $OPT['make'] || $make || 'make'
  $mantype = $OPT['mantype']
  mflags = ($OPT['make-flags'] || '').strip
  mflags = ($OPT['mflags'] || '').strip if mflags.empty?

  $mflags = Shellwords.shellwords(mflags)
  if arg = $mflags.first
    arg.insert(0, '-') if /\A[^-][^=]*\Z/ =~ arg
  end

  $make, *rest = Shellwords.shellwords($make)
  $mflags.unshift(*rest) unless rest.empty?

  def $mflags.set?(flag)
    grep(/\A-(?!-).*#{'%c' % flag}/i) { return true }
    false
  end

  if $mflags.set?(?n)
    $dryrun = true
  else
    $mflags << '-n' if $dryrun
  end

  $mflags << "DESTDIR=#{$destdir}"

  $continue = $mflags.set?(?k)
end

parse_args()

include FileUtils::Verbose
include FileUtils::NoWrite if $dryrun
@fileutils_output = STDOUT
@fileutils_label = ''

def install(src, dest, options = {})
  options[:preserve] = true
  super
end

$made_dirs = {}
def makedirs(dirs)
  dirs = fu_list(dirs)
  dirs.reject! do |dir|
    $made_dirs.fetch(dir) do
      $made_dirs[dir] = true
      File.directory?(dir)
    end
  end
  super(dirs, :mode => 0755, :verbose => true) unless dirs.empty?
end

def with_destdir(dir)
  return dir if $destdir.empty?
  dir = dir.sub(/\A\w:/, '') if File::PATH_SEPARATOR == ';'
  $destdir + dir
end

exeext = CONFIG["EXEEXT"]

ruby_install_name = CONFIG["ruby_install_name"]
rubyw_install_name = CONFIG["rubyw_install_name"]

version = CONFIG["ruby_version"]
bindir = with_destdir(CONFIG["bindir"])
libdir = with_destdir(CONFIG["libdir"])
rubylibdir = with_destdir(CONFIG["rubylibdir"])
archlibdir = with_destdir(CONFIG["archdir"])
sitelibdir = with_destdir(CONFIG["sitelibdir"])
sitearchlibdir = with_destdir(CONFIG["sitearchdir"])
mandir = with_destdir(File.join(CONFIG["mandir"], "man"))
configure_args = Shellwords.shellwords(CONFIG["configure_args"])
enable_shared = CONFIG["ENABLE_SHARED"] == 'yes'
dll = CONFIG["LIBRUBY_SO"]
lib = CONFIG["LIBRUBY"]
arc = CONFIG["LIBRUBY_A"]

makedirs [bindir, libdir, rubylibdir, archlibdir, sitelibdir, sitearchlibdir]

ruby_bin = File.join(bindir, ruby_install_name)

install ruby_install_name+exeext, ruby_bin+exeext, :mode => 0755
if rubyw_install_name and !rubyw_install_name.empty?
  install rubyw_install_name+exeext, bindir, :mode => 0755
end
install dll, bindir, :mode => 0755 if enable_shared and dll != lib
install lib, libdir, :mode => 0755 unless lib == arc
install arc, libdir, :mode => 0644
install "config.h", archlibdir, :mode => 0644
install "rbconfig.rb", archlibdir, :mode => 0644
if CONFIG["ARCHFILE"]
  for file in CONFIG["ARCHFILE"].split
    install file, archlibdir, :mode => 0644
  end
end

if dll == lib and dll != arc
  for link in CONFIG["LIBRUBY_ALIASES"].split
    ln_sf(dll, File.join(libdir, link))
  end
end

Dir.chdir CONFIG["srcdir"]

ruby_shebang = File.join(CONFIG["bindir"], ruby_install_name)
if File::ALT_SEPARATOR
  ruby_bin_dosish = ruby_shebang.tr(File::SEPARATOR, File::ALT_SEPARATOR)
end
for src in Dir["bin/*"]
  next unless File.file?(src)
  next if /\/[.#]|(\.(old|bak|orig|rej|diff|patch|core)|~|\/core)$/i =~ src

  name = ruby_install_name.sub(/ruby/, File.basename(src))
  dest = File.join(bindir, name)

  install src, dest, :mode => 0755

  next if $dryrun

  shebang = ''
  body = ''
  open(dest, "r+") { |f|
    shebang = f.gets
    body = f.read

    if shebang.sub!(/^\#!.*?ruby\b/) {"#!" + ruby_shebang}
      f.rewind
      f.print shebang, body
      f.truncate(f.pos)
    end
  }

  if ruby_bin_dosish
    batfile = File.join(CONFIG["bindir"], name + ".bat")
    open(with_destdir(batfile), "w") { |b|
      b.print <<EOH, shebang, body, <<EOF
@echo off
if not "%~d0" == "~d0" goto WinNT
#{ruby_bin_dosish} -x "#{batfile}" %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofruby
:WinNT
"%~dp0#{ruby_install_name}" -x "%~f0" %*
goto endofruby
EOH
__END__
:endofruby
EOF
    }
  end
end

for f in Dir["lib/**/*{.rb,help-message}"]
  dir = File.dirname(f).sub!(/\Alib/, rubylibdir) || rubylibdir
  makedirs dir
  install f, dir, :mode => 0644
end

for f in Dir["*.h"]
  install f, archlibdir, :mode => 0644
end

if RUBY_PLATFORM =~ /mswin32|mingw|bccwin32/
  makedirs File.join(archlibdir, "win32")
  install "win32/win32.h", File.join(archlibdir, "win32"), :mode => 0644
end

for mdoc in Dir["*.[1-9]"]
  next unless File.file?(mdoc) and open(mdoc){|fh| fh.read(1) == '.'}

  section = mdoc[-1,1]

  destdir = mandir + section
  destfile = File.join(destdir, mdoc.sub(/ruby/, ruby_install_name))

  makedirs destdir

  if $mantype == "doc"
    install mdoc, destfile, :mode => 0644
  else
    require 'mdoc2man.rb'

    w = Tempfile.open(mdoc)

    open(mdoc) { |r|
      Mdoc2Man.mdoc2man(r, w)
    }

    w.close

    install w.path, destfile, :mode => 0644
  end
end

# vi:set sw=2:
