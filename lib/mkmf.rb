# module to create Makefile for extension modules
# invoke like: ruby -r mkmf extconf.rb

require 'rbconfig'
require 'fileutils'
require 'shellwords'

CONFIG = Config::MAKEFILE_CONFIG
ORIG_LIBPATH = ENV['LIB']

SRC_EXT = ["c", "cc", "m", "cxx", "cpp", "C"]
$static = $config_h = nil

unless defined? $configure_args
  $configure_args = {}
  args = CONFIG["configure_args"]
  if ENV["CONFIGURE_ARGS"]
    args << " " << ENV["CONFIGURE_ARGS"]
  end
  for arg in Shellwords::shellwords(args)
    arg, val = arg.split('=', 2)
    next unless arg
    arg.tr!('_', '-')
    if arg.sub!(/^(?!--)/, '--')
      val or next
      arg.downcase!
    end
    next if /^--(?:top|topsrc|src|cur)dir$/ =~ arg
    $configure_args[arg] = val || true
  end
  for arg in ARGV
    arg, val = arg.split('=', 2)
    next unless arg
    arg.tr!('_', '-')
    if arg.sub!(/^(?!--)/, '--')
      val or next
      arg.downcase!
    end
    $configure_args[arg] = val || true
  end
end

$srcdir = CONFIG["srcdir"]
$libdir = CONFIG["libdir"]
$rubylibdir = CONFIG["rubylibdir"]
$archdir = CONFIG["archdir"]
$sitedir = CONFIG["sitedir"]
$sitelibdir = CONFIG["sitelibdir"]
$sitearchdir = CONFIG["sitearchdir"]

$mswin = /mswin/ =~ RUBY_PLATFORM
$bccwin = /bccwin/ =~ RUBY_PLATFORM
$mingw = /mingw/ =~ RUBY_PLATFORM
$cygwin = /cygwin/ =~ RUBY_PLATFORM
$human = /human/ =~ RUBY_PLATFORM
$netbsd = /netbsd/ =~ RUBY_PLATFORM
$os2 = /os2/ =~ RUBY_PLATFORM

def config_string(key, config = CONFIG)
  s = config[key] and !s.empty? and block_given? ? yield(s) : s
end

def dir_re(dir)
  Regexp.new('\$(?:\('+dir+'\)|\{'+dir+'\})(?:\$\(target_prefix\)|\{target_prefix\})?')
end

INSTALL_DIRS = [
  [dir_re('commondir'), "$(RUBYCOMMONDIR)"],
  [dir_re("sitedir"), "$(RUBYCOMMONDIR)"],
  [dir_re('rubylibdir'), "$(RUBYLIBDIR)"],
  [dir_re('archdir'), "$(RUBYARCHDIR)"],
  [dir_re('sitelibdir'), "$(RUBYLIBDIR)"],
  [dir_re('sitearchdir'), "$(RUBYARCHDIR)"]
]

def map_dir(dir, map = nil)
  map ||= INSTALL_DIRS
  map.inject(dir) {|dir, (orig, new)| dir.gsub(orig, new)}
end

libdir = File.dirname(__FILE__)
$extmk = libdir != Config::CONFIG["rubylibdir"]
if not $extmk and File.exist? Config::CONFIG["archdir"] + "/ruby.h"
  $hdrdir = $topdir = Config::CONFIG["archdir"]
elsif File.exist? $srcdir + "/ruby.h"
  $topdir = Config::CONFIG["compile_dir"]
  $hdrdir = $srcdir
else
  abort "can't find header files for ruby."
end

OUTFLAG = CONFIG['OUTFLAG']
CPPOUTFILE = CONFIG['CPPOUTFILE']

CONFTEST_C = "conftest.c"

class String
  def quote
    /\s/ =~ self ? "\"#{self}\"" : self
  end
end
class Array
  def quote
    map {|s| s.quote}
  end
end

def rm_f(*files)
  FileUtils.rm_f(Dir[files.join("\0")])
end

def modified?(target, times)
  (t = File.mtime(target)) rescue return nil
  Array === times or times = [times]
  t if times.all? {|n| n <= t}
end

def merge_libs(*libs)
  libs.inject([]) do |x, y|
    xy = x & y
    xn = yn = 0
    y = y.inject([]) {|ary, e| ary.last == e ? ary : ary << e}
    y.each_with_index do |v, yi|
      if xy.include?(v)
        xi = [x.index(v), xn].max()
        x[xi, 1] = y[yn..yi]
        xn, yn = xi + (yi - yn + 1), yi + 1
      end
    end
    x.concat(y[yn..-1] || [])
  end
end

module Logging
  @log = nil
  @logfile = 'mkmf.log'
  @orgerr = $stderr.dup
  @orgout = $stdout.dup

  def self::open
    @log ||= File::open(@logfile, 'w')
    @log.sync = true
    $stderr.reopen(@log)
    $stdout.reopen(@log)
    yield
  ensure
    $stderr.reopen(@orgerr)
    $stdout.reopen(@orgout)
  end

  def self::message(*s)
    @log ||= File::open(@logfile, 'w')
    @log.sync = true
    @log.printf(*s)
  end

  def self::logfile file
    @logfile = file
    if @log and not @log.closed?
      @log.flush
      @log.close
      @log = nil
    end
  end
  
  def self::postpone
    tmplog = "mkmftmp.log"
    open do
      log, *save = @log, @logfile, @orgout, @orgerr
      @log, @logfile, @orgout, @orgerr = nil, tmplog, log, log
      begin
        log.print(open {yield})
        @log.close
        File::open(tmplog) {|t| FileUtils.copy_stream(t, log)}
      ensure
        @log, @logfile, @orgout, @orgerr = log, *save
        rm_f tmplog
      end
    end
  end
end

def xsystem command
  Config.expand(command)
  Logging::open do
    puts command.quote
    system(command)
  end
end

def xpopen command, *mode, &block
  Config.expand(command)
  Logging::open do
    case mode[0]
    when nil, /^r/
      puts "#{command} |"
    else
      puts "| #{command}"
    end
    IO.popen(command, *mode, &block)
  end
end

def log_src(src)
  Logging::message <<"EOM", src
checked program was:
/* begin */
%s/* end */

EOM
end

def create_tmpsrc(src)
  src = yield(src) if block_given?
  src = src.sub(/[^\n]\z/, "\\&\n")
  open(CONFTEST_C, "wb") do |cfile|
    cfile.print src
  end
  src
end

def try_do(src, command, &b)
  src = create_tmpsrc(src, &b)
  xsystem(command)
ensure
  log_src(src)
end

def link_command(ldflags, opt="", libpath=$LIBPATH)
  Config::expand(TRY_LINK.dup,
		 'hdrdir' => $hdrdir,
		 'src' => CONFTEST_C,
		 'INCFLAGS' => $INCFLAGS,
		 'CPPFLAGS' => $CPPFLAGS,
		 'CFLAGS' => "#$CFLAGS",
		 'ARCH_FLAG' => "#$ARCH_FLAG",
		 'LDFLAGS' => "#$LDFLAGS #{ldflags}",
		 'LIBPATH' => libpathflag(libpath),
		 'LOCAL_LIBS' => "#$LOCAL_LIBS #$libs",
		 'LIBS' => "#$LIBRUBYARG_STATIC #{opt} #$LIBS")
end

def cc_command(opt="")
  "$(CC) -c #$INCFLAGS -I#{$hdrdir} " \
  "#$CPPFLAGS #$CFLAGS #$ARCH_FLAG #{opt} #{CONFTEST_C}"
end

def cpp_command(outfile, opt="")
  "$(CPP) #$INCFLAGS -I#{$hdrdir} " \
  "#$CPPFLAGS #$CFLAGS #{opt} #{CONFTEST_C} #{outfile}"
end

def libpathflag(libpath=$LIBPATH)
  libpath.map{|x|
    (x == "$(topdir)" ? LIBPATHFLAG : LIBPATHFLAG+RPATHFLAG) % x
  }.join
end

def try_link0(src, opt="", &b)
  try_do(src, link_command("", opt), &b)
end

def try_link(src, opt="", &b)
  try_link0(src, opt, &b)
ensure
  rm_f "conftest*", "c0x32*"
end

def try_compile(src, opt="", &b)
  try_do(src, cc_command(opt), &b)
ensure
  rm_f "conftest*"
end

def try_cpp(src, opt="", &b)
  try_do(src, cpp_command(CPPOUTFILE, opt), &b)
ensure
  rm_f "conftest*"
end

def cpp_include(header)
  if header
    header = [header] unless header.kind_of? Array
    header.map {|h| "#include <#{h}>\n"}.join
  else
    ""
  end
end

def try_static_assert(expr, headers = nil, opt = "", &b)
  headers = cpp_include(headers)
  try_compile(<<SRC, opt, &b)
#{COMMON_HEADERS}
#{headers}
/*top*/
int tmp[(#{expr}) ? 1 : -1];
SRC
end

def try_constant(const, headers = nil, opt = "", &b)
  headers = cpp_include(headers)
  if CROSS_COMPILING
    unless try_compile(<<"SRC", opt, &b)
#{COMMON_HEADERS}
#{headers}
/*top*/
int tmp = #{const};
SRC
      return nil
    end
    if try_static_assert("#{const} < 0", headers, opt)
      neg = true
      const = "-(#{const})"
    elsif try_static_assert("#{const} == 0", headers, opt)
      return 0
    end
    upper = 1
    until try_static_assert("#{const} < #{upper}", headers, opt)
      lower = upper
      upper <<= 1
    end
    return nil unless lower
    until try_static_assert("#{const} == #{upper}", headers, opt)
      if try_static_assert("#{const} > #{(upper+lower)/2}", headers, opt)
        lower = (upper+lower)/2
      else
        upper = (upper+lower)/2
      end
    end
    upper = -upper if neg
    return upper
  else
    src = %{#{COMMON_HEADERS}
#{headers}
#include <stdio.h>
/*top*/
int main() {printf("%d\\n", (int)(#{const})); return 0;}
}
    if try_link0(src, opt, &b)
      xpopen("./conftest") do |f|
        return Integer(f.gets)
      end
    end
  end
  nil
end

def try_func(func, libs, headers = nil, &b)
  headers = cpp_include(headers)
  try_link(<<"SRC", libs, &b) or try_link(<<"SRC", libs, &b)
#{headers}
/*top*/
int main() { return 0; }
int t() { #{func}(); return 0; }
SRC
#{COMMON_HEADERS}
#{headers}
/*top*/
int main() { return 0; }
int t() { void ((*volatile p)()); p = (void ((*)()))#{func}; return 0; }
SRC
end

def egrep_cpp(pat, src, opt = "", &b)
  src = create_tmpsrc(src, &b)
  xpopen(cpp_command('', opt)) do |f|
    if Regexp === pat
      puts("    ruby -ne 'print if #{pat.inspect}'")
      f.grep(pat) {|l|
	puts "#{f.lineno}: #{l}"
	return true
      }
      false
    else
      puts("    egrep '#{pat}'")
      begin
	stdin = $stdin.dup
	$stdin.reopen(f)
	system("egrep", pat)
      ensure
	$stdin.reopen(stdin)
      end
    end
  end
ensure
  rm_f "conftest*"
  log_src(src)
end

def macro_defined?(macro, src, opt = "", &b)
  src = src.sub(/[^\n]\z/, "\\&\n")
  try_cpp(src + <<"SRC", opt, &b)
/*top*/
#ifndef #{macro}
# error
#endif
SRC
end

def try_run(src, opt = "", &b)
  if try_link0(src, opt, &b)
    xsystem("./conftest")
  else
    nil
  end
ensure
  rm_f "conftest*"
end

def install_files(mfile, ifiles, map = nil, srcprefix = nil)
  ifiles or return
  srcprefix ||= '$(srcdir)'
  Config::expand(srcdir = srcprefix.dup)
  dirs = []
  path = Hash.new {|h, i| h[i] = dirs.push([i])[-1]}
  ifiles.each do |files, dir, prefix|
    dir = map_dir(dir, map)
    prefix = %r|\A#{Regexp.quote(prefix)}/?| if prefix
    if( files[0,2] == "./" )
      # install files which are in current working directory.
      files = files[2..-1]
      len = nil
    else
      # install files which are under the $(srcdir).
      files = File.join(srcdir, files)
      len = srcdir.size
    end
    f = nil
    Dir.glob(files) do |f|
      f[0..len] = "" if len
      d = File.dirname(f)
      d.sub!(prefix, "") if prefix
      d = (d.empty? || d == ".") ? dir : File.join(dir, d)
      f = File.join(srcprefix, f) if len
      path[d] << f
    end
    unless len or f
      d = File.dirname(files)
      d.sub!(prefix, "") if prefix
      d = (d.empty? || d == ".") ? dir : File.join(dir, d)
      path[d] << files
    end
  end
  dirs
end

def install_rb(mfile, dest, srcdir = nil)
  install_files(mfile, [["lib/**/*.rb", dest, "lib"]], nil, srcdir)
end

def append_library(libs, lib)
  format(LIBARG, lib) + " " + libs
end

def message(*s)
  unless $extmk and not $VERBOSE
    printf(*s)
    $stdout.flush
  end
end

def checking_for(m)
  f = caller[0][/in `(.*)'$/, 1] and f << ": " #` for vim
  m = "checking for #{m}... "
  message "%s", m
  a = r = nil
  Logging::postpone do
    r = yield
    a = r ? "yes\n" : "no\n"
    "#{f}#{m}-------------------- #{a}\n"
  end
  message(a)
  Logging::message "--------------------\n\n"
  r
end

def have_library(lib, func = nil, header=nil, &b)
  func = "main" if !func or func.empty?
  lib = with_config(lib+'lib', lib)
  checking_for "#{func}() in #{LIBARG%lib}" do
    if COMMON_LIBS.include?(lib)
      true
    else
      libs = append_library($libs, lib)
      if try_func(func, libs, header, &b)
        $libs = libs
        true
      else
        false
      end
    end
  end
end

def find_library(lib, func, *paths, &b)
  func = "main" if !func or func.empty?
  lib = with_config(lib+'lib', lib)
  checking_for "#{func}() in #{LIBARG%lib}" do
    libpath = $LIBPATH
    libs = append_library($libs, lib)
    begin
      until r = try_func(func, libs, &b) or paths.empty?
	$LIBPATH = libpath | [paths.shift]
      end
      if r
	$libs = libs
	libpath = nil
      end
    ensure
      $LIBPATH = libpath if libpath
    end
    r
  end
end

def have_func(func, headers = nil, &b)
  checking_for "#{func}()" do
    if try_func(func, $libs, headers, &b)
      $defs.push(format("-DHAVE_%s", func.upcase))
      true
    else
      false
    end
  end
end

def have_header(header, &b)
  checking_for header do
    if try_cpp(cpp_include(header), &b)
      $defs.push(format("-DHAVE_%s", header.tr("a-z./\055", "A-Z___")))
      true
    else
      false
    end
  end
end

def have_struct_member(type, member, header = nil, &b)
  checking_for "#{type}.#{member}" do
    if try_compile(<<"SRC", &b)
#{COMMON_HEADERS}
#{cpp_include(header)}
/*top*/
int main() { return 0; }
int s = (char *)&((#{type}*)0)->#{member} - (char *)0;
SRC
      $defs.push(format("-DHAVE_ST_%s", member.upcase))
      true
    else
      false
    end
  end
end

def have_type(type, header = nil, opt = "", &b)
  checking_for type do
    header = cpp_include(header)
    if try_compile(<<"SRC", opt, &b) or (/\A\w+\z/n =~ type && try_compile(<<"SRC", opt, &b))
#{COMMON_HEADERS}
#{header}
/*top*/
static #{type} t;
SRC
#{COMMON_HEADERS}
#{header}
/*top*/
static #{type} *t;
SRC
      $defs.push(format("-DHAVE_TYPE_%s", type.strip.upcase.tr_s("^A-Z0-9_", "_")))
      true
    else
      false
    end
  end
end

def check_sizeof(type, header = nil, &b)
  expr = "sizeof(#{type})"
  m = "checking size of #{type}... "
  message "%s", m
  Logging::message "check_sizeof: %s--------------------\n", m
  if size = try_constant(expr, header, &b)
    $defs.push(format("-DSIZEOF_%s=%d", type.upcase.tr_s("^A-Z0-9_", "_"), size))
  end
  message(a = size ? "#{size}\n" : "failed\n")
  Logging::message "-------------------- %s\n", a
  size
end

def find_executable0(bin, path = nil)
  path = (path || ENV['PATH']).split(File::PATH_SEPARATOR)
  ext = config_string('EXEEXT')
  file = nil
  path.each do |dir|
    return file if File.executable?(file = File.join(dir, bin))
    return file if ext and File.executable?(file << ext)
  end
  nil
end

def find_executable(bin, path = nil)
  checking_for bin do
    find_executable0(bin, path)
  end
end

def arg_config(config, default=nil)
  $configure_args.fetch(config.tr('_', '-'), default)
end

def with_config(config, default=nil)
  unless /^--with[-_]/ =~ config
    config = '--with-' + config
  end
  arg_config(config, default)
end

def enable_config(config, default=nil)
  if arg_config("--enable-"+config)
    true
  elsif arg_config("--disable-"+config)
    false
  else
    default
  end
end

def create_header(header = "extconf.h")
  message "creating %s\n", header
  if $defs.length > 0
    sym = header.tr("a-z./\055", "A-Z___")
    open(header, "w") do |hfile|
      hfile.print "#ifndef #{sym}\n#define #{sym}\n"
      for line in $defs
	case line
	when /^-D([^=]+)(?:=(.*))?/
	  hfile.print "#define #$1 #{$2 || 1}\n"
	when /^-U(.*)/
	  hfile.print "#undef #$1\n"
	end
      end
      hfile.print "#endif\n"
    end
  end
end

def dir_config(target, idefault=nil, ldefault=nil)
  if dir = with_config(target + "-dir", (idefault unless ldefault))
    defaults = dir.split(File::PATH_SEPARATOR)
    idefault = ldefault = nil
  end

  idir = with_config(target + "-include", idefault)
  ldir = with_config(target + "-lib", ldefault)

#  idirs = idir ? idir.split(File::PATH_SEPARATOR) : []
  idirs = idir.split(File::PATH_SEPARATOR) rescue []
  if defaults
    idirs.concat(defaults.collect {|dir| dir + "/include"})
    idir = ([idir] + idirs).compact.join(File::PATH_SEPARATOR)
  end
  unless idirs.empty?
    idirs.collect! {|dir| "-I" + dir}
    idirs -= Shellwords.shellwords($CPPFLAGS)
    unless idirs.empty?
      $CPPFLAGS = (idirs.quote << $CPPFLAGS).join(" ")
    end
  end

  ldirs = ldir ? ldir.split(File::PATH_SEPARATOR) : []
  if defaults
    ldirs.concat(defaults.collect {|dir| dir + "/lib"})
    ldir = ([ldir] + ldirs).compact.join(File::PATH_SEPARATOR)
  end
  $LIBPATH = ldirs | $LIBPATH

  [idir, ldir]
end

def pkg_config(pkg)
  unless defined?($PKGCONFIG)
    if pkgconfig = with_config("pkg-config", !CROSS_COMPILING && "pkg-config")
      find_executable0(pkgconfig) or pkgconfig = nil
    end
    $PKGCONFIG = pkgconfig
  end
  if $PKGCONFIG and system("#{$PKGCONFIG} --exists #{pkg}")
    cflags = `#{$PKGCONFIG} --cflags #{pkg}`.chomp
    ldflags = `#{$PKGCONFIG} --libs #{pkg}`.chomp
    libs = `#{$PKGCONFIG} --libs-only-l #{pkg}`.chomp
    ldflags = (Shellwords.shellwords(ldflags) - Shellwords.shellwords(libs)).quote.join(" ")
    $CFLAGS += " " << cflags
    $LDFLAGS += " " << ldflags
    $libs += " " << libs
    Logging::message "package configuration for %s\n", pkg
    Logging::message "cflags: %s\nldflags: %s\nlibs: %s\n\n",
                     cflags, ldflags, libs
    [cflags, ldflags, libs]
  end
end

def with_destdir(dir)
  /^\$[\(\{]/ =~ dir ? dir : "$(DESTDIR)"+dir
end

def winsep(s)
  s.tr('/', '\\')
end

def configuration(srcdir)
  mk = []
  mk << %{
SHELL = /bin/sh

#### Start of system configuration section. ####

srcdir = #{srcdir}
topdir = #{$topdir}
hdrdir = #{$extmk ? $hdrdir : '$(topdir)'}
VPATH = #{$mingw && CONFIG['build_os'] == 'cygwin' ? '$(shell cygpath -u $(srcdir))' : '$(srcdir)'}
}
  drive = File::PATH_SEPARATOR == ';' ? /\A\w:/ : /\A/
  if destdir = CONFIG["prefix"].scan(drive)[0] and !destdir.empty?
    mk << "\nDESTDIR = #{destdir}\n"
  end
  CONFIG.each do |key, var|
    next unless /prefix$/ =~ key
    mk << "#{key} = #{with_destdir(var.sub(drive, ''))}\n"
  end
  CONFIG.each do |key, var|
    next if /^abs_/ =~ key
    next unless /^(?:src|top|(.*))dir$/ =~ key and $1
    mk << "#{key} = #{with_destdir(var.sub(drive, ''))}\n"
  end
  mk << %{
CC = #{CONFIG['CC']}
LIBRUBY = #{CONFIG['LIBRUBY']}
LIBRUBY_A = #{CONFIG['LIBRUBY_A']}
LIBRUBYARG_SHARED = #$LIBRUBYARG_SHARED
LIBRUBYARG_STATIC = #$LIBRUBYARG_STATIC

CFLAGS   = #{CONFIG['CCDLFLAGS'] unless $static} #$CFLAGS #$ARCH_FLAG
CPPFLAGS = -I. -I$(topdir) -I$(hdrdir) -I$(srcdir) #{$defs.join(" ")} #{$CPPFLAGS}
CXXFLAGS = $(CFLAGS) #{CONFIG['CXXFLAGS']}
DLDFLAGS = #$LDFLAGS #$DLDFLAGS #$ARCH_FLAG
LDSHARED = #{CONFIG['LDSHARED']}
AR = #{CONFIG['AR']}
EXEEXT = #{CONFIG['EXEEXT']}

RUBY_INSTALL_NAME = #{CONFIG['RUBY_INSTALL_NAME']}
RUBY_SO_NAME = #{CONFIG['RUBY_SO_NAME']}
arch = #{CONFIG['arch']}
sitearch = #{CONFIG['sitearch']}
ruby_version = #{Config::CONFIG['ruby_version']}
ruby = #{$ruby}
RUBY = #{($nmake && !$extmk && !$configure_args.has_key?('--ruby')) ? '$(ruby:/=\)' : '$(ruby)'}
RM = $(RUBY) -run -e rm -- -f
MAKEDIRS = $(RUBY) -run -e mkdir -- -p
INSTALL_PROG = $(RUBY) -run -e install -- -vpm 0755
INSTALL_DATA = $(RUBY) -run -e install -- -vpm 0644

#### End of system configuration section. ####

}
  if $nmake == ?b
    mk.each do |x|
      x.gsub!(/^(MAKEDIRS|INSTALL_(?:PROG|DATA))+\s*=.*\n/) do
        "!ifndef " + $1 + "\n" +
        $& +
	"!endif\n"
      end
    end
  end
  mk
end

def dummy_makefile(srcdir)
  configuration(srcdir) << "all install: Makefile\n" << CLEANINGS
end

def create_makefile(target, srcprefix = nil)
  $target = target
  libpath = $LIBPATH
  message "creating Makefile\n"
  rm_f "conftest*"
  if CONFIG["DLEXT"] == $OBJEXT
    for lib in libs = $libs.split
      lib.sub!(/-l(.*)/, %%"lib\\1.#{$LIBEXT}"%)
    end
    $defs.push(format("-DEXTLIB='%s'", libs.join(",")))
  end

  if target.include?('/')
    target_prefix, target = File.split(target)
    target_prefix[0,0] = '/'
  else
    target_prefix = ""
  end

  srcprefix ||= '$(srcdir)'
  Config::expand(srcdir = srcprefix.dup)

  unless $objs then
    $objs = []
    for f in Dir[File.join(srcdir, "*.{#{SRC_EXT.join(%q{,})}}")]
      $objs.push(File.basename(f, ".*") << "." << $OBJEXT)
    end
  else
    for i in $objs
      i.sub!(/\.o\z/, ".#{$OBJEXT}")
    end
  end
  $objs = $objs.join(" ")

  target = nil if $objs == ""

  if target and EXPORT_PREFIX
    if File.exist?(File.join(srcdir, target + '.def'))
      deffile = "$(srcdir)/$(TARGET).def"
      unless EXPORT_PREFIX.empty?
        makedef = %{-pe "sub!(/^(?=\\w)/,'#{EXPORT_PREFIX}') unless 1../^EXPORTS$/i"}
      end
    else
      makedef = %{-e "puts 'EXPORTS', '#{EXPORT_PREFIX}Init_$(TARGET)'"}
    end
    if makedef
      $distcleanfiles << '$(DEFFILE)'
      origdef = deffile
      deffile = "$(TARGET)-$(arch).def"
    end
  end

  libpath = libpathflag(libpath)

  dllib = target ? "$(TARGET).#{CONFIG['DLEXT']}" : ""
  staticlib = target ? "$(TARGET).#$LIBEXT" : ""
  mfile = open("Makefile", "wb")
  mfile.print configuration(srcdir)
  mfile.print %{
LIBPATH = #{libpath}
DEFFILE = #{deffile}

CLEANFILES = #{$cleanfiles.join(' ')}
DISTCLEANFILES = #{$distcleanfiles.join(' ')}

target_prefix = #{target_prefix}
LOCAL_LIBS = #{$LOCAL_LIBS}
LIBS = #{$LIBRUBYARG} #{$libs} #{$LIBS}
OBJS = #{$objs}
TARGET = #{target}
DLLIB = #{dllib}
STATIC_LIB = #{staticlib}
}
  if $extmk
    mfile.print %{
RUBYCOMMONDIR = $(rubylibdir)
RUBYLIBDIR    = $(rubylibdir)$(target_prefix)
RUBYARCHDIR   = $(archdir)$(target_prefix)
}
  else
    mfile.print %{
RUBYCOMMONDIR = $(sitedir)$(target_prefix)
RUBYLIBDIR    = $(sitelibdir)$(target_prefix)
RUBYARCHDIR   = $(sitearchdir)$(target_prefix)
}
  end
  mfile.print %{
CLEANLIBS     = "$(TARGET).{lib,exp,il?,tds,map}" $(DLLIB)
CLEANOBJS     = "*.{#{$OBJEXT},#{$LIBEXT},s[ol],pdb,bak}"

all:		#{target ? "$(DLLIB)" : "Makefile"}
static:		$(STATIC_LIB)
}
  mfile.print CLEANINGS
  dirs = []
  if not $static and target
    dirs << (dir = "$(RUBYARCHDIR)")
    mfile.print("install: #{dir}\n")
    f = "$(DLLIB)"
    dest = "#{dir}/#{f}"
    mfile.print "install: #{dest}\n"
    mfile.print "#{dest}: #{f} #{dir}\n\t@$(INSTALL_PROG) #{f} #{dir}\n"
  end
  for i in [[["lib/**/*.rb", "$(RUBYLIBDIR)", "lib"]], $INSTALLFILES]
    files = install_files(mfile, i, nil, srcprefix) or next
    for dir, *files in files
      unless dirs.include?(dir)
	dirs << dir
	mfile.print("install: #{dir}\n")
      end
      files.each do |f|
	dest = "#{dir}/#{File.basename(f)}"
	mfile.print("install: #{dest}\n")
	mfile.print("#{dest}: #{f} #{dir}\n\t@$(INSTALL_DATA) #{f} #{dir}\n")
      end
    end
  end
  if dirs.empty?
    mfile.print("install:\n")
  else
    dirs.each {|dir| mfile.print "#{dir}:\n\t@$(MAKEDIRS) #{dir}\n"}
  end

  mfile.print "\nsite-install: install\n\n"

  return unless target

  mfile.print ".SUFFIXES: .#{SRC_EXT.join(' .')} .#{$OBJEXT}\n"
  mfile.print "\n"

  %w[cc cpp cxx C].each do |ext|
    COMPILE_RULES.each do |rule|
      mfile.printf(rule, ext, $OBJEXT)
      mfile.printf("\n\t%s\n\n", COMPILE_CXX)
    end
  end
  %w[c].each do |ext|
    COMPILE_RULES.each do |rule|
      mfile.printf(rule, ext, $OBJEXT)
      mfile.printf("\n\t%s\n\n", COMPILE_C)
    end
  end

  if makedef
    mfile.print "$(DLLIB): $(OBJS) $(DEFFILE)\n\t"
  else
    mfile.print "$(DLLIB): $(OBJS)\n\t"
  end
  mfile.print "@-$(RM) $@\n\t"
  mfile.print "@-$(RM) $(TARGET).lib\n\t" if $mswin
  mfile.print LINK_SO, "\n\n"
  mfile.print "$(STATIC_LIB): $(OBJS)\n\t"
  mfile.print "$(AR) #{config_string('ARFLAGS') || 'cru '}$@ $(OBJS)"
  if ranlib = config_string('RANLIB')
    mfile.print "\n\t@-#{ranlib} $(DLLIB) 2> /dev/null || true"
  end
  mfile.print "\n\n"
  if makedef
    mfile.print "$(DEFFILE): #{origdef}\n"
    mfile.print "\t$(RUBY) #{makedef} #{origdef} > $@\n\n"
  end

  depend = File.join(srcdir, "depend")
  if File.exist?(depend)
    open(depend, "r") do |dfile|
      mfile.printf "###\n"
      while line = dfile.gets()
	line.gsub!(/\.o\b/, ".#{$OBJEXT}")
	line.gsub!(/(\s)([^\s\/]+\.[ch])/, '\1{$(srcdir)}\2') if $nmake
	line.gsub!(/\$\(hdrdir\)\/config.h/, $config_h) if $config_h
	mfile.print line
      end
    end
  end
ensure
  mfile.close if mfile
end

def init_mkmf(config = CONFIG)
  $enable_shared = config['ENABLE_SHARED'] == 'yes'
  $defs = []
  $CFLAGS = with_config("cflags", arg_config("CFLAGS", config["CFLAGS"])).dup
  $ARCH_FLAG = with_config("arch_flag", arg_config("ARCH_FLAG", config["ARCH_FLAG"])).dup
  $CPPFLAGS = with_config("cppflags", arg_config("CPPFLAGS", config["CPPFLAGS"])).dup
  $LDFLAGS = (with_config("ldflags") || "").dup
  $INCFLAGS = "-I$(topdir)"
  $DLDFLAGS = with_config("dldflags", arg_config("DLDFLAGS", config["DLDFLAGS"])).dup
  $LIBEXT = config['LIBEXT'].dup
  $OBJEXT = config["OBJEXT"].dup
  $LIBS = "#{config['LIBS']} #{config['DLDLIBS']}"
  $LIBRUBYARG = ""
  $LIBRUBYARG_STATIC = config['LIBRUBYARG_STATIC']
  $LIBRUBYARG_SHARED = config['LIBRUBYARG_SHARED']
  $LIBPATH = $extmk ? ["$(topdir)"] : CROSS_COMPILING ? [] : ["$(libdir)"]
  $INSTALLFILES = nil

  $objs = nil
  $libs = ""
  if $enable_shared or Config.expand(config["LIBRUBY"].dup) != Config.expand(config["LIBRUBY_A"].dup)
    $LIBRUBYARG = config['LIBRUBYARG']
  end

  $LOCAL_LIBS = ""

  $cleanfiles = []
  $distcleanfiles = []

  dir_config("opt")
end

init_mkmf

$make = with_config("make-prog", ENV["MAKE"] || "make")
make, = Shellwords.shellwords($make)
$nmake = nil
case
when $mswin
  $nmake = ?m if /nmake/i =~ make
when $bccwin
  $nmake = ?b if /Borland/i =~ `#{make} -h`
end

Config::CONFIG["srcdir"] = CONFIG["srcdir"] =
  $srcdir = arg_config("--srcdir", File.dirname($0))
$configure_args["--topsrcdir"] ||= $srcdir
Config::CONFIG["topdir"] = CONFIG["topdir"] =
  $curdir = arg_config("--curdir", Dir.pwd)
$configure_args["--topdir"] ||= $curdir
$ruby = arg_config("--ruby", File.join(Config::CONFIG["bindir"], CONFIG["ruby_install_name"]))

split = Shellwords.method(:shellwords).to_proc

EXPORT_PREFIX = config_string('EXPORT_PREFIX') {|s| s.strip}

hdr = []
config_string('COMMON_MACROS') do |s|
  Shellwords.shellwords(s).each do |s|
    /(.*?)(?:=(.*))/ =~ s
    hdr << "#define #$1 #$2"
  end
end
config_string('COMMON_HEADERS') do |s|
  Shellwords.shellwords(s).each {|s| hdr << "#include <#{s}>"}
end
COMMON_HEADERS = (hdr.join("\n") unless hdr.empty?)
COMMON_LIBS = config_string('COMMON_LIBS', &split) || []

COMPILE_RULES = config_string('COMPILE_RULES', &split) || %w[.%s.%s:]
COMPILE_C = config_string('COMPILE_C') || '$(CC) $(CFLAGS) $(CPPFLAGS) -c $<'
COMPILE_CXX = config_string('COMPILE_CXX') || '$(CXX) $(CXXFLAGS) $(CPPFLAGS) -c $<'
TRY_LINK = config_string('TRY_LINK') ||
  "$(CC) #{OUTFLAG}conftest $(INCFLAGS) -I$(hdrdir) $(CPPFLAGS) " \
  "$(CFLAGS) $(src) $(LIBPATH) $(LDFLAGS) $(ARCH_FLAG) $(LOCAL_LIBS) $(LIBS)"
LINK_SO = config_string('LINK_SO') ||
  if CONFIG["DLEXT"] == $OBJEXT
    "ld $(DLDFLAGS) -r -o $(DLLIB) $(OBJS)\n"
  else
    "$(LDSHARED) $(DLDFLAGS) $(LIBPATH) #{OUTFLAG}$(DLLIB) " \
    "$(OBJS) $(LOCAL_LIBS) $(LIBS)"
  end
LIBPATHFLAG = config_string('LIBPATHFLAG') || ' -L"%s"'
RPATHFLAG = config_string('RPATHFLAG') || ''
LIBARG = config_string('LIBARG') || '-l%s'

CLEANINGS = "
clean:
		@$(RM) $(CLEANLIBS) $(CLEANOBJS) $(CLEANFILES)

distclean:	clean
		@$(RM) Makefile extconf.h conftest.* mkmf.log
		@$(RM) core ruby$(EXEEXT) *~ $(DISTCLEANFILES)

realclean:	distclean
"
