#!./miniruby

load "./rbconfig.rb"
include RbConfig

srcdir = File.dirname(__FILE__)
$:.unshift File.expand_path("lib", srcdir)
require 'fileutils'
require 'shellwords'
require 'optparse'
require 'optparse/shellwords'
require 'tempfile'

STDOUT.sync = true
File.umask(0)

def parse_args()
  $mantype = 'doc'
  $destdir = nil
  $extout = nil
  $make = 'make'
  $mflags = []
  $install = []
  $installed_list = nil
  $dryrun = false
  $rdocdir = nil
  opt = OptionParser.new
  opt.on('-n') {$dryrun = true}
  opt.on('--dest-dir=DIR') {|dir| $destdir = dir}
  opt.on('--extout=DIR') {|dir| $extout = (dir unless dir.empty?)}
  opt.on('--make=COMMAND') {|make| $make = make}
  opt.on('--mantype=MAN') {|man| $mantype = man}
  opt.on('--make-flags=FLAGS', '--mflags', Shellwords) do |v|
    if arg = v.first
      arg.insert(0, '-') if /\A[^-][^=]*\Z/ =~ arg
    end
    $mflags.concat(v)
  end
  opt.on('-i', '--install=TYPE',
         [:local, :bin, :lib, :man, :ext, :"ext-arch", :"ext-comm", :rdoc]) do |ins|
    $install << ins
  end
  opt.on('--installed-list [FILENAME]') {|name| $installed_list = name}
  opt.on('--rdoc-output [DIR]') {|dir| $rdocdir = dir}

  opt.parse! rescue abort [$!.message, opt].join("\n")

  $make, *rest = Shellwords.shellwords($make)
  $mflags.unshift(*rest) unless rest.empty?

  def $mflags.set?(flag)
    grep(/\A-(?!-).*#{'%c' % flag}/i) { return true }
    false
  end
  def $mflags.defined?(var)
    grep(/\A#{var}=(.*)/) {return $1}
    false
  end

  if $mflags.set?(?n)
    $dryrun = true
  else
    $mflags << '-n' if $dryrun
  end

  $destdir ||= $mflags.defined?("DESTDIR")
  if $extout ||= $mflags.defined?("EXTOUT")
    Config.expand($extout)
  end

  $continue = $mflags.set?(?k)

  if $installed_list ||= $mflags.defined?('INSTALLED_LIST')
    Config.expand($installed_list, Config::CONFIG)
    $installed_list = open($installed_list, "ab")
    $installed_list.sync = true
  end

  $rdocdir ||= $mflags.defined?('RDOCOUT')
end

parse_args()

include FileUtils
include FileUtils::NoWrite if $dryrun
@fileutils_output = STDOUT
@fileutils_label = ''

$install_procs = Hash.new {[]}
def install?(*types, &block)
  $install_procs[:all] <<= block
  types.each do |type|
    $install_procs[type] <<= block
  end
end

def install(src, dest, options = {})
  options[:preserve] = true
  super(src, with_destdir(dest), options)
  if $installed_list
    dest = File.join(dest, File.basename(src)) if $made_dirs[dest]
    $installed_list.puts dest
  end
end

def ln_sf(src, dest)
  super(src, with_destdir(dest))
  $installed_list.puts dest if $installed_list
end

$made_dirs = {}
def makedirs(dirs)
  dirs = fu_list(dirs)
  dirs.collect! do |dir|
    realdir = with_destdir(dir)
    realdir unless $made_dirs.fetch(dir) do
      $made_dirs[dir] = true
      $installed_list.puts(File.join(dir, "")) if $installed_list
      File.directory?(realdir)
    end
  end.compact!
  super(dirs, :mode => 0755) unless dirs.empty?
end

def install_recursive(src, dest, options = {})
  noinst = options.delete(:no_install)
  subpath = src.size..-1
  Dir.glob("#{src}/**/*", File::FNM_DOTMATCH) do |src|
    next if /\A\.{1,2}\z/ =~ (base = File.basename(src))
    next if noinst and File.fnmatch?(noinst, File.basename(src))
    d = dest + src[subpath]
    if File.directory?(src)
      makedirs(d)
    else
      install src, d
    end
  end
end

def open_for_install(path, mode, &block)
  unless $dryrun
    open(with_destdir(path), mode, &block)
  end
  $installed_list.puts path if /^w/ =~ mode and $installed_list
end

def with_destdir(dir)
  return dir if !$destdir or $destdir.empty?
  dir = dir.sub(/\A\w:/, '') if File::PATH_SEPARATOR == ';'
  $destdir + dir
end

exeext = CONFIG["EXEEXT"]

ruby_install_name = CONFIG["ruby_install_name"]
rubyw_install_name = CONFIG["rubyw_install_name"]

version = CONFIG["ruby_version"]
bindir = CONFIG["bindir"]
libdir = CONFIG["libdir"]
rubylibdir = CONFIG["rubylibdir"]
archlibdir = CONFIG["archdir"]
sitelibdir = CONFIG["sitelibdir"]
sitearchlibdir = CONFIG["sitearchdir"]
mandir = File.join(CONFIG["mandir"], "man")
configure_args = Shellwords.shellwords(CONFIG["configure_args"])
enable_shared = CONFIG["ENABLE_SHARED"] == 'yes'
dll = CONFIG["LIBRUBY_SO"]
lib = CONFIG["LIBRUBY"]
arc = CONFIG["LIBRUBY_A"]

install?(:local, :arch, :bin) do
  puts "installing binary commands"

  makedirs [bindir, libdir, archlibdir]

  install ruby_install_name+exeext, bindir, :mode => 0755
  if rubyw_install_name and !rubyw_install_name.empty?
    install rubyw_install_name+exeext, bindir, :mode => 0755
  end
  if enable_shared and dll != lib
    install dll, bindir, :mode => 0755
  end
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
end

if $extout
  extout = "#$extout"
  install?(:ext, :arch, :'ext-arch') do
    puts "installing extension objects"
    makedirs [archlibdir, sitearchlibdir]
    if noinst = CONFIG["no_install_files"] and noinst.empty?
      noinst = nil
    end
    install_recursive("#{extout}/#{CONFIG['arch']}", archlibdir, :no_install => noinst)
  end
  install?(:ext, :comm, :'ext-comm') do
    puts "installing extension scripts"
    makedirs [rubylibdir, sitelibdir]
    install_recursive("#{extout}/common", rubylibdir)
  end
end

install?(:rdoc) do
  if $rdocdir
    puts "installing rdoc"

    ridatadir = File.join(CONFIG['datadir'], 'ri/$(MAJOR).$(MINOR)/system')
    Config.expand(ridatadir)
    makedirs [ridatadir]
    install_recursive($rdocdir, ridatadir)
  end
end

install?(:local, :comm, :bin) do
  puts "installing command scripts"

  Dir.chdir srcdir
  makedirs [bindir, rubylibdir]

  ruby_shebang = File.join(bindir, ruby_install_name)
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
    open_for_install(dest, "r+") { |f|
      shebang = f.gets
      body = f.read

      if shebang.sub!(/^\#!.*?ruby\b/) {"#!" + ruby_shebang}
        f.rewind
        f.print shebang, body
        f.truncate(f.pos)
      end
    }

    if ruby_bin_dosish
      batfile = File.join(bindir, name + ".bat")
      open_for_install(batfile, "wb") {|b|
        b.print((<<EOH+shebang+body+<<EOF).gsub(/\r?\n/, "\r\n"))
@echo off
@if not "%~d0" == "~d0" goto WinNT
#{ruby_bin_dosish} -x "#{batfile}" %1 %2 %3 %4 %5 %6 %7 %8 %9
@goto endofruby
:WinNT
"%~dp0#{ruby_install_name}" -x "%~f0" %*
@goto endofruby
EOH
__END__
:endofruby
EOF
      }
    end
  end
end

install?(:local, :comm, :lib) do
  puts "installing library scripts"

  Dir.chdir srcdir
  makedirs [rubylibdir]

  for f in Dir["lib/**/*{.rb,help-message}"]
    dir = File.dirname(f).sub!(/\Alib/, rubylibdir) || rubylibdir
    makedirs dir
    install f, dir, :mode => 0644
  end
end

install?(:local, :arch, :lib) do
  puts "installing headers"

  Dir.chdir(srcdir)
  makedirs [archlibdir]
  for f in Dir["*.h"]
    install f, archlibdir, :mode => 0644
  end

  if RUBY_PLATFORM =~ /mswin32|mingw|bccwin32/
    win32libdir = File.join(archlibdir, "win32")
    makedirs win32libdir
    install "win32/win32.h", win32libdir, :mode => 0644
  end
end

install?(:local, :comm, :man) do
  puts "installing manpages"

  Dir.chdir(srcdir)
  for mdoc in Dir["*.[1-9]"]
    next unless File.file?(mdoc) and open(mdoc){|fh| fh.read(1) == '.'}

    destdir = mandir + mdoc[/(\d+)$/]
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
end

$install.concat ARGV.collect {|n| n.intern}
$install << :local << :ext if $install.empty?
$install.each do |inst|
  $install_procs[inst].each do |block|
    dir = Dir.pwd
    begin
      block.call
    ensure
      Dir.chdir(dir)
    end
  end
end

# vi:set sw=2:
