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

def parse_args(argv = ARGV)
  $mantype = 'doc'
  $destdir = nil
  $extout = nil
  $make = 'make'
  $mflags = []
  $install = []
  $installed_list = nil
  $dryrun = false
  $rdocdir = nil
  $data_mode = 0644
  $prog_mode = 0755
  $dir_mode = nil
  $script_mode = nil
  $cmdtype = ('bat' if File::ALT_SEPARATOR == '\\')
  mflags = []
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
         [:local, :bin, :"bin-arch", :"bin-comm", :lib, :man, :ext, :"ext-arch", :"ext-comm", :rdoc]) do |ins|
    $install << ins
  end
  opt.on('--data-mode=OCTAL-MODE', OptionParser::OctalInteger) do |mode|
    $data_mode = mode
  end
  opt.on('--prog-mode=OCTAL-MODE', OptionParser::OctalInteger) do |mode|
    $prog_mode = mode
  end
  opt.on('--dir-mode=OCTAL-MODE', OptionParser::OctalInteger) do |mode|
    $dir_mode = mode
  end
  opt.on('--script-mode=OCTAL-MODE', OptionParser::OctalInteger) do |mode|
    $script_mode = mode
  end
  opt.on('--installed-list [FILENAME]') {|name| $installed_list = name}
  opt.on('--rdoc-output [DIR]') {|dir| $rdocdir = dir}
  opt.on('--cmd-type=TYPE', %w[bat cmd plain]) {|cmd| $cmdtype = (cmd unless cmd == 'plain')}

  opt.order!(argv) do |v|
    case v
    when /\AINSTALL[-_]([-\w]+)=(.*)/
      argv.unshift("--#{$1.tr('_', '-')}=#{$2}")
    when /\A\w[-\w+]*=\z/
      mflags << v
    when /\A\w[-\w+]*\z/
      $install << v.intern
    else
      raise OptionParser::InvalidArgument, v
    end
  end rescue abort [$!.message, opt].join("\n")

  $make, *rest = Shellwords.shellwords($make)
  $mflags.unshift(*rest) unless rest.empty?
  $mflags.unshift(*mflags)

  def $mflags.set?(flag)
    grep(/\A-(?!-).*#{flag.chr}/i) { return true }
    false
  end
  def $mflags.defined?(var)
    grep(/\A#{var}=(.*)/) {return block_given? ? yield($1) : $1}
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

  $dir_mode ||= $prog_mode | 0700
  $script_mode ||= $prog_mode
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
  super(dirs, :mode => $dir_mode) unless dirs.empty?
end

def install_recursive(srcdir, dest, options = {})
  opts = options.clone
  noinst = opts.delete(:no_install)
  glob = opts.delete(:glob) || "*"
  subpath = srcdir.size..-1
  Dir.glob("#{srcdir}/**/#{glob}") do |src|
    case base = File.basename(src)
    when /\A\#.*\#\z/, /~\z/
      next
    end
    if noinst
      if Array === noinst
        next if noinst.any? {|n| File.fnmatch?(n, base)}
      else
        next if File.fnmatch?(noinst, base)
      end
    end
    d = dest + src[subpath]
    if File.directory?(src)
      makedirs(d)
    else
      makedirs(File.dirname(d))
      install src, d, opts
    end
  end
end

def open_for_install(path, mode)
  data = open(realpath = with_destdir(path), "rb") {|f| f.read} rescue nil
  newdata = yield
  unless $dryrun
    unless newdata == data
      open(realpath, "wb", mode) {|f| f.write newdata}
    end
    File.chmod(mode, realpath)
  end
  $installed_list.puts path if $installed_list
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
vendorlibdir = CONFIG["vendorlibdir"]
vendorarchlibdir = CONFIG["vendorarchdir"]
mandir = File.join(CONFIG["mandir"], "man")
configure_args = Shellwords.shellwords(CONFIG["configure_args"])
enable_shared = CONFIG["ENABLE_SHARED"] == 'yes'
dll = CONFIG["LIBRUBY_SO"]
lib = CONFIG["LIBRUBY"]
arc = CONFIG["LIBRUBY_A"]

install?(:local, :arch, :bin, :'bin-arch') do
  puts "installing binary commands"

  makedirs [bindir, libdir, archlibdir]

  install ruby_install_name+exeext, bindir, :mode => $prog_mode
  if rubyw_install_name and !rubyw_install_name.empty?
    install rubyw_install_name+exeext, bindir, :mode => $prog_mode
  end
  if enable_shared and dll != lib
    install dll, bindir, :mode => $prog_mode
  end
  install lib, libdir, :mode => $prog_mode unless lib == arc
  install arc, libdir, :mode => $data_mode
  install "config.h", archlibdir, :mode => $data_mode
  install "rbconfig.rb", archlibdir, :mode => $data_mode
  if CONFIG["ARCHFILE"]
    for file in CONFIG["ARCHFILE"].split
      install file, archlibdir, :mode => $data_mode
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
    makedirs [archlibdir, sitearchlibdir, vendorarchlibdir]
    if noinst = CONFIG["no_install_files"] and noinst.empty?
      noinst = nil
    end
    install_recursive("#{extout}/#{CONFIG['arch']}", archlibdir, :no_install => noinst, :mode => $prog_mode)
  end
  install?(:ext, :comm, :'ext-comm') do
    puts "installing extension scripts"
    makedirs [rubylibdir, sitelibdir, vendorlibdir]
    install_recursive("#{extout}/common", rubylibdir, :mode => $data_mode)
  end
end

install?(:rdoc) do
  if $rdocdir
    puts "installing rdoc"

    ridatadir = File.join(CONFIG['datadir'], 'ri/$(MAJOR).$(MINOR)/system')
    Config.expand(ridatadir)
    makedirs [ridatadir]
    install_recursive($rdocdir, ridatadir, :mode => $data_mode)
  end
end

install?(:local, :comm, :bin, :'bin-comm') do
  puts "installing command scripts"

  Dir.chdir srcdir
  makedirs [bindir, rubylibdir]

  ruby_shebang = File.join(bindir, ruby_install_name)
  if File::ALT_SEPARATOR
    ruby_bin = ruby_shebang.tr(File::SEPARATOR, File::ALT_SEPARATOR)
  end
  for src in Dir["bin/*"]
    next unless File.file?(src)
    next if /\/[.#]|(\.(old|bak|orig|rej|diff|patch|core)|~|\/core)$/i =~ src

    name = ruby_install_name.sub(/ruby/, File.basename(src))

    shebang = ''
    body = ''
    open(src, "rb") do |f|
      shebang = f.gets
      body = f.read
    end
    shebang.sub!(/^\#!.*?ruby\b/) {"#!" + ruby_shebang}
    shebang.sub!(/\r$/, '')
    body.gsub!(/\r$/, '')

    cmd = File.join(bindir, name)
    cmd << ".#{$cmdtype}" if $cmdtype
    open_for_install(cmd, $script_mode) do
      case $cmdtype
      when "bat"
        "#{<<EOH}#{shebang}#{body}#{<<EOF}".gsub(/$/, "\r")
@echo off
@if not "%~d0" == "~d0" goto WinNT
#{ruby_bin} -x "#{cmd}" %1 %2 %3 %4 %5 %6 %7 %8 %9
@goto endofruby
:WinNT
"%~dp0#{ruby_install_name}" -x "%~f0" %*
@goto endofruby
EOH
__END__
:endofruby
EOF
      when "cmd"
        "#{<<EOH}#{shebang}#{body}"
@"%~dp0#{ruby_install_name}" -x "%~f0" %*
@exit /b %ERRORLEVEL%
EOH
      else
        shebang + body
      end
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
    install f, dir, :mode => $data_mode
  end
end

install?(:local, :arch, :lib) do
  puts "installing headers"

  Dir.chdir(srcdir)
  makedirs [archlibdir]
  for f in Dir["*.h"]
    install f, archlibdir, :mode => $data_mode
  end

  if RUBY_PLATFORM =~ /mswin32|mingw|bccwin32/
    win32libdir = File.join(archlibdir, "win32")
    makedirs win32libdir
    install "win32/win32.h", win32libdir, :mode => $data_mode
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
      install mdoc, destfile, :mode => $data_mode
    else
      require 'mdoc2man.rb'

      w = Tempfile.open(mdoc)

      open(mdoc) { |r|
        Mdoc2Man.mdoc2man(r, w)
      }

      w.close

      install w.path, destfile, :mode => $data_mode
    end
  end
end

$install << :local << :ext if $install.empty?
$install.each do |inst|
  if !(procs = $install_procs[inst]) || procs.empty?
    next warn("unknown install target - #{inst}")
  end
  procs.each do |block|
    dir = Dir.pwd
    begin
      block.call
    ensure
      Dir.chdir(dir)
    end
  end
end

# vi:set sw=2:
