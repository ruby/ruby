# module to create Makefile for extension modules
# invoke like: ruby -r mkmf extconf.rb

require 'rbconfig'
require 'shellwords'

CONFIG = Config::MAKEFILE_CONFIG
ORIG_LIBPATH = ENV['LIB']

SRC_EXT = ["c", "cc", "m", "cxx", "cpp", "C"]

unless defined? $configure_args
  $configure_args = {}
  args = CONFIG["configure_args"]
  if ENV["CONFIGURE_ARGS"]
    args << " " << ENV["CONFIGURE_ARGS"]
  end
  for arg in Shellwords::shellwords(args)
    arg, val = arg.split('=', 2)
    if arg.sub!(/^(?!--)/, '--')
      val or next
      arg.downcase!
    end
    next if /^--(?:top|topsrc|src|cur)dir$/ =~ arg
    $configure_args[arg] = val || true
  end
  for arg in ARGV
    arg, val = arg.split('=', 2)
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

$extmk = /extmk\.rb/ =~ $0
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

if not $extmk and File.exist? Config::CONFIG["archdir"] + "/ruby.h"
  $hdrdir = $archdir
elsif File.exist? $srcdir + "/ruby.h"
  $hdrdir = $srcdir
else
  STDERR.print "can't find header files for ruby.\n"
  exit 1
end
$topdir = $hdrdir

OUTFLAG = CONFIG['OUTFLAG']
CPPOUTFILE = CONFIG['CPPOUTFILE']

CONFTEST_C = "conftest.c"

$INSTALLFILES ||= nil

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
  targets = []
  for file in files
    targets.concat Dir[file]
  end
  if not targets.empty?
    File::chmod(0777, *targets)
    File::unlink(*targets)
  end
end

def older(target, *files)
  mtime = proc do |f|
    Time === f ? f : f.respond_to?(:mtime) ? f.mtime : File.mtime(f) rescue nil
  end
  t = mtime[target] or return true
  for f in files
    return true if t < (mtime[f] or next)
  end
  false
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
end

def xsystem command
  Config.expand(command)
  Logging::open do
    command = Shellwords.shellwords(command)
    puts command.quote.join(' ')
    system(*command)
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
  Logging::message <<"EOM"
checked program was:
/* begin */
#{src}/* end */

EOM
end

def create_tmpsrc(src)
  open(CONFTEST_C, "w") do |cfile|
    cfile.print src
  end
end

def try_do(src, command)
  src += "\n" unless /\n\z/ =~ src
  create_tmpsrc(src)
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
		 'LDFLAGS' => "#$LDFLAGS #{ldflags}",
		 'LIBPATH' => libpathflag(libpath),
		 'LOCAL_LIBS' => "#$LOCAL_LIBS #$libs",
		 'LIBS' => "#$LIBRUBYARG #{opt} #$LIBS")
end

def cc_command(opt="")
  "$(CC) -c #$INCFLAGS -I#{$hdrdir} " \
  "#$CPPFLAGS #$CFLAGS #{opt} #{CONFTEST_C}"
end

def cpp_command(outfile, opt="")
  "$(CPP) #$INCFLAGS -I#{$hdrdir} " \
  "#$CPPFLAGS #$CFLAGS #{outfile} #{opt} #{CONFTEST_C}"
end

def libpathflag(libpath=$LIBPATH)
  libpath.map{|x| LIBPATHFLAG % %["#{x}"]}.join
end

def try_link0(src, opt="")
  try_do(src, link_command("", opt))
end

def try_link(src, opt="")
  try_link0(src, opt)
ensure
  rm_f "conftest*", "c0x32*"
end

def try_compile(src, opt="")
  try_do(src, cc_command(opt))
ensure
  rm_f "conftest*"
end

def try_cpp(src, opt="")
  try_do(src, cpp_command(CPPOUTFILE, opt))
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

def try_func(func, libs, headers = nil)
  headers = cpp_include(headers)
  try_link(<<"SRC", libs) or try_link(<<"SRC", libs)
#{COMMON_HEADERS}
#{headers}
int main() { return 0; }
int t() { #{func}(); return 0; }
SRC
#{COMMON_HEADERS}
#{headers}
int main() { return 0; }
int t() { void ((*volatile p)()); p = (void ((*)()))#{func}; return 0; }
SRC
end

def egrep_cpp(pat, src, opt="")
  src += "\n" unless /\n\z/ =~ src
  create_tmpsrc(src)
  xpopen(cpp_command('', opt)) do |f|
    if Regexp === pat
      puts("    ruby -ne 'print if /#{pat.source}/'")
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

def macro_defined?(macro, src, opt="")
  try_cpp(src + <<"SRC", opt)
#ifndef #{macro}
# error
#endif
SRC
end

def try_run(src, opt="")
  if try_link0(src, opt)
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
    prefix = %r"\A#{Regexp.quote(prefix)}/?" if prefix
    if( files[0,2] == "./" )
      # install files which are in current working directory.
      files = files[2..-1]
      len = nil
    else
      # install files which are under the $(srcdir).
      files = File.join(srcdir, files)
      len = srcdir.size
    end
    Dir.glob(files) do |f|
      f[0..len] = "" if len
      d = File.dirname(f)
      d.sub!(prefix, "") if prefix
      d = (d.empty? || d == ".") ? dir : File.join(dir, d)
      f = File.join(srcprefix, f) if len
      path[d] << f
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
  f = caller[0][/in \`(.*)\'$/, 1] and f << ": "
  m = "checking for #{m}... "
  message m
  Logging::message "#{f}#{m}\n"
  r = yield
  message(r ? "yes\n" : "no\n")
  r
end

def have_library(lib, func="main")
  checking_for "#{func}() in -l#{lib}" do
    libs = append_library($libs, lib)
    if func && func != "" && COMMON_LIBS.include?(lib)
      true
    elsif try_func(func, libs)
      $libs = libs
      true
    else
      false
    end
  end
end

def find_library(lib, func, *paths)
  checking_for "#{func}() in -l#{lib}" do
    libpath = $LIBPATH
    libs = append_library($libs, lib)
    begin
      until r = try_func(func, libs) or paths.empty?
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

def have_func(func, header=nil)
  checking_for "#{func}()" do
    if try_func(func, $libs, header)
      $defs.push(format("-DHAVE_%s", func.upcase))
      true
    else
      false
    end
  end
end

def have_header(header)
  checking_for header do
    if try_cpp(cpp_include(header))
      $defs.push(format("-DHAVE_%s", header.tr("a-z./\055", "A-Z___")))
      true
    else
      false
    end
  end
end

def have_struct_member(type, member, header=nil)
  checking_for "#{type}.#{member}" do
    if try_compile(<<"SRC")
#{COMMON_HEADERS}
#{cpp_include(header)}
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
  $configure_args.fetch(config, default)
end

def with_config(config, default=nil)
  unless /^--with-/ =~ config
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
  message "creating #{header}\n"
  if $defs.length > 0
    sym = header.tr("a-z./\055", "A-Z___")
    open(header, "w") do |hfile|
      hfile.print "#ifndef #{sym}\n#define #{sym}\n"
      for line in $defs
	case line
	when /^-D(.*)(?:=(.*))?/
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
    idefault = dir + "/include"
    ldefault = dir + "/lib"
  end

  idir = with_config(target + "-include", idefault)
  ldir = with_config(target + "-lib", ldefault)

  if idir
    idircflag = "-I" + idir
    $CPPFLAGS += " " + idircflag unless $CPPFLAGS.split.include?(idircflag)
  end

  if ldir
    $LIBPATH << ldir unless $LIBPATH.include?(ldir)
  end

  [idir, ldir]
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
hdrdir = #{$hdrdir}
VPATH = $(srcdir)
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

CFLAGS   = #{CONFIG['CCDLFLAGS'] unless $static} #$CFLAGS
CPPFLAGS = -I. -I$(topdir) -I$(hdrdir) -I$(srcdir) #{$defs.join(" ")} #{$CPPFLAGS}
CXXFLAGS = $(CFLAGS) #{CONFIG['CXXFLAGS']}
DLDFLAGS = #$LDFLAGS #{CONFIG['DLDFLAGS']} #$DLDFLAGS
LDSHARED = #{CONFIG['LDSHARED']}
AR = #{CONFIG['AR']}
EXEEXT = #{CONFIG['EXEEXT']}

RUBY_INSTALL_NAME = #{CONFIG['RUBY_INSTALL_NAME']}
RUBY_SO_NAME = #{CONFIG['RUBY_SO_NAME']}
arch = #{CONFIG['arch']}
sitearch = #{CONFIG['sitearch']}
ruby_version = #{Config::CONFIG['ruby_version']}
RUBY = #{$ruby}
RM = $(RUBY) -rftools -e "File::rm_f(*ARGV.map do|x|Dir[x]end.flatten.uniq)"
MAKEDIRS = $(RUBY) -r ftools -e 'File::makedirs(*ARGV)'
INSTALL_PROG = $(RUBY) -r ftools -e 'File::install(ARGV[0], ARGV[1], 0555, true)'
INSTALL_DATA = $(RUBY) -r ftools -e 'File::install(ARGV[0], ARGV[1], 0644, true)'

#### End of system configuration section. ####

}
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

  cleanfiles = []
  distcleanfiles = []
  if EXPORT_PREFIX
    origdef = target + '.def'
    deffile = EXPORT_PREFIX + origdef
    unless File.exist? deffile
      if File.exist? File.join(srcdir, deffile)
	deffile = File.join srcdir, deffile
      elsif !EXPORT_PREFIX.empty? and File.exist?(origdef = File.join(srcdir, origdef))
	open(origdef) do |d|
	  open(deffile, 'wb') do |f|
	    d.each do |l|
	      f.print l
	      break if /^EXPORTS$/i =~ l
	    end
	    d.each do |l|
	      f.print l.sub(/\S/, EXPORT_PREFIX+'\&')
	    end
	  end
	end
      else
	open(deffile, 'wb') do |f|
	  f.print "EXPORTS\n", EXPORT_PREFIX, "Init_", target, "\n"
	end
      end
    end
    distcleanfiles << deffile unless deffile == origdef
  end

  libpath = libpathflag(libpath)

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

  mfile = open("Makefile", "wb")
  mfile.print configuration(srcdir)
  mfile.print %{
LIBPATH = #{libpath}
DEFFILE = #{deffile}

CLEANFILES = #{cleanfiles.join(' ')}
DISTCLEANFILES = #{distcleanfiles.join(' ')}

target_prefix = #{target_prefix}
LOCAL_LIBS = #{$LOCAL_LIBS}
LIBS = #{$LIBRUBYARG} #{$libs} #{$LIBS}
OBJS = #{$objs}
TARGET = #{target}
DLLIB = $(TARGET).#{$static ? $LIBEXT : CONFIG['DLEXT']}
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
all:		$(DLLIB)

clean::
		@$(RM) "$(TARGET).{lib,exp,il?,tds,map}" $(DLLIB)
		@$(RM) "*.{#{$OBJEXT},#{$LIBEXT},s[ol],pdb,bak}"
}
  mfile.print CLEANINGS
  dirs = []
  unless $static
    dirs << (dir = "$(RUBYARCHDIR)")
    mfile.print("install: #{dir}\n")
    f = "$(DLLIB)"
    dest = "#{dir}/#{f}"
    mfile.print "install: #{dest}\n"
    mfile.print "#{dest}: #{f}\n\t@$(INSTALL_PROG) #{f} #{dir}\n"
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
	mfile.print("#{dest}: #{f}\n\t@$(INSTALL_DATA) #{f} #{dir}\n")
      end
    end
  end
  if dirs.empty?
    mfile.print("install:\n")
  else
    dirs.each {|dir| mfile.print "#{dir}:\n\t@$(MAKEDIRS) #{dir}\n"}
  end

  mfile.print "\nsite-install: install\n\n"

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

  mfile.print "$(DLLIB): $(OBJS)\n\t"
  mfile.print "@-$(RM) $@\n\t"
  if $static
    mfile.print "$(AR) #{config_string('ARFLAGS') || 'cru '}$(DLLIB) $(OBJS)"
    if ranlib = config_string('RANLIB')
      mfile.print "\n\t@-#{ranlib} $(DLLIB) 2> /dev/null || true"
    end
  else
    mfile.print LINK_SO
  end
  mfile.print "\n\n"

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
  mfile.close
end

def init_mkmf(config = CONFIG)
  $defs = []
  $CFLAGS = with_config("cflags", arg_config("CFLAGS", config["CFLAGS"])).dup
  $CPPFLAGS = with_config("cppflags", arg_config("CPPFLAGS", config["CPPFLAGS"])).dup
  $LDFLAGS = with_config("ldflags", arg_config("LDFLAGS", config["LDFLAGS"])).dup
  $INCFLAGS = "-I#{$topdir}"
  $DLDFLAGS = ""
  $LIBEXT = config['LIBEXT'].dup
  $OBJEXT = config["OBJEXT"].dup
  $LIBS = "#{config['LIBS']} #{config['DLDLIBS']}"
  $LIBRUBYARG = config['LIBRUBYARG']
  $LIBPATH = []

  $objs = nil
  $libs = ""
  if $configure_args['--enable-shared'] or config["LIBRUBY"] != config["LIBRUBY_A"]
    $LIBPATH = ["$(topdir)"]
    $LIBPATH.unshift("$(libdir)") unless $extmk or defined? CROSS_COMPILING
  end
  $LIBPATH << "$(archdir)"

  $LOCAL_LIBS = ""
  dir_config("opt")
end

init_mkmf
dir_config("opt")

$make = with_config("make-prog", ENV["MAKE"] || "make")
$nmake = nil
case
when $mswin
  $nmake = ?m if /nmake/i =~ $make
when $bccwin
  $nmake = ?b if /Borland/i =~ `#$make -h`
end

Config::CONFIG["srcdir"] = CONFIG["srcdir"] =
  $srcdir = arg_config("--srcdir", File.dirname($0))
$configure_args["--topsrcdir"] ||= $srcdir
Config::CONFIG["topdir"] = CONFIG["topdir"] =
  $curdir = arg_config("--curdir", Dir.pwd)
$configure_args["--topdir"] ||= $curdir
$ruby = arg_config("--ruby", CONFIG["ruby_install_name"])

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
  "$(CFLAGS) $(src) $(LIBPATH) $(LDFLAGS) $(LOCAL_LIBS) $(LIBS)"
LINK_SO = config_string('LINK_SO') ||
  if CONFIG["DLEXT"] == $OBJEXT
    "ld $(DLDFLAGS) -r -o $(DLLIB) $(OBJS)\n"
  else
    "$(LDSHARED) $(DLDFLAGS) $(LIBPATH) #{OUTFLAG}$(DLLIB) " \
    "$(OBJS) $(LOCAL_LIBS) $(LIBS)"
  end
LIBPATHFLAG = config_string('LIBPATHFLAG') || ' -L%s'
LIBARG = config_string('LIBARG') || '-l%s'

CLEANINGS = "
clean::
		@$(RM) $(CLEANFILES)

distclean::	clean
		@$(RM) Makefile extconf.h conftest.* mkmf.log
		@$(RM) core ruby$(EXEEXT) *~ $(DISTCLEANFILES)

realclean::	distclean
"
