# module to create Makefile for extension modules
# invoke like: ruby -r mkmf extconf.rb

require 'rbconfig'
require 'find'

CONFIG = Config::MAKEFILE_CONFIG
ORIG_LIBPATH = ENV['LIB']

SRC_EXT = ["c", "cc", "m", "cxx", "cpp", "C"]

$config_cache = CONFIG["compile_dir"]+"/ext/config.cache"

$srcdir = CONFIG["srcdir"]
$libdir = CONFIG["libdir"]
$rubylibdir = CONFIG["rubylibdir"]
$archdir = CONFIG["archdir"]
$sitedir = CONFIG["sitedir"]
$sitelibdir = CONFIG["sitelibdir"]
$sitearchdir = CONFIG["sitearchdir"]

if File.exist? Config::CONFIG["archdir"] + "/ruby.h"
  $hdrdir = $archdir
elsif File.exist? $srcdir + "/ruby.h"
  $hdrdir = $srcdir
else
  STDERR.print "can't find header files for ruby.\n"
  exit 1
end
$topdir = $hdrdir
# $hdrdir.gsub!('/', '\\') if RUBY_PLATFORM =~ /mswin32/

CFLAGS = CONFIG["CFLAGS"]
if RUBY_PLATFORM == "m68k-human"
  CFLAGS.gsub!(/-c..-stack=[0-9]+ */, '')
elsif RUBY_PLATFORM =~ /-nextstep|-rhapsody|-darwin/
  CFLAGS.gsub!( /-arch\s\w*/, '' )
end

$log = open('mkmf.log', 'w')

if /mswin32/ =~ RUBY_PLATFORM
  OUTFLAG = '-Fe'
else
  OUTFLAG = '-o '
end
LINK = "#{CONFIG['CC']} #{OUTFLAG}conftest -I#{$hdrdir} #{CFLAGS} -I#{CONFIG['includedir']} %s %s #{CONFIG['LDFLAGS']} %s conftest.c %s %s #{CONFIG['LIBS']}"
CPP = "#{CONFIG['CPP']} -E %s -I#{$hdrdir} #{CFLAGS} -I#{CONFIG['includedir']} %s %s conftest.c"

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

$orgerr = $stderr.dup
$orgout = $stdout.dup
def xsystem command
  Config.expand(command)
  if $DEBUG
    puts command
    return system(command)
  end
  $stderr.reopen($log) 
  $stdout.reopen($log) 
  puts command
  r = system(command)
  $stderr.reopen($orgerr)
  $stdout.reopen($orgout)
  return r
end

def try_link0(src, opt="")
  cfile = open("conftest.c", "w")
  cfile.print src
  cfile.close
  ldflags = $LDFLAGS
  if /mswin32/ =~ RUBY_PLATFORM and !$LIBPATH.empty?
    ENV['LIB'] = ($LIBPATH + [ORIG_LIBPATH]).compact.join(';')
  else
    $LDFLAGS = ldflags.dup
    $LIBPATH.each {|d| $LDFLAGS << " -L" + d}
  end
  begin
    xsystem(format(LINK, $CFLAGS, $CPPFLAGS, $LDFLAGS, opt, $LOCAL_LIBS))
  ensure
    $LDFLAGS = ldflags
    ENV['LIB'] = ORIG_LIBPATH if /mswin32/ =~ RUBY_PLATFORM
  end
end

def try_link(src, opt="")
  begin
    try_link0(src, opt)
  ensure
    rm_f "conftest*"
  end
end

def try_cpp(src, opt="")
  cfile = open("conftest.c", "w")
  cfile.print src
  cfile.close
  begin
    xsystem(format(CPP, $CPPFLAGS, $CFLAGS, opt))
  ensure
    rm_f "conftest*"
  end
end

def egrep_cpp(pat, src, opt="")
  cfile = open("conftest.c", "w")
  cfile.print src
  cfile.close
  begin
    xsystem(format(CPP+"|egrep #{pat}", $CPPFLAGS, $CFLAGS, opt))
  ensure
    rm_f "conftest*"
  end
end

def try_run(src, opt="")
  begin
    if try_link0(src, opt)
      if xsystem("./conftest")
	true
      else
	false
      end
    else
      nil
    end
  ensure
    rm_f "conftest*"
  end
end

def install_rb(mfile, dest, srcdir = nil)
  libdir = "lib"
  libdir = srcdir + "/" + libdir if srcdir
  path = []
  dir = []
  if File.directory? libdir
    Find.find(libdir) do |f|
      next unless /\.rb$/ =~ f
      f = f[libdir.length+1..-1]
      path.push f
      dir |= [File.dirname(f)]
    end
  end
  for f in dir
    if f == "."
      mfile.printf "\t@$(RUBY) -r ftools -e 'File::makedirs(*ARGV)' %s\n", dest
    else
      mfile.printf "\t@$(RUBY) -r ftools -e 'File::makedirs(*ARGV)' %s/%s\n", dest, f
    end
  end
  for f in path
    d = '/' + File::dirname(f)
    d = '' if d == '/.' 
    mfile.printf "\t@$(RUBY) -r ftools -e 'File::install(ARGV[0], ARGV[1], 0644, true)' %s/%s %s%s\n", libdir, f, dest, d
  end
end

def append_library(libs, lib)
  if /mswin32/ =~ RUBY_PLATFORM
    lib + ".lib " + libs
  else
    "-l" + lib + " " + libs
  end
end

def have_library(lib, func="main")
  printf "checking for %s() in -l%s... ", func, lib
  STDOUT.flush

  if func && func != ""
    libs = append_library($libs, lib)
    if /mswin32|mingw/ =~ RUBY_PLATFORM
      if lib == 'm'
	print "yes\n"
	return true
      end
      r = try_link(<<"SRC", libs)
#include <windows.h>
#include <winsock.h>
int main() { return 0; }
int t() { #{func}(); return 0; }
SRC
      unless r
        r = try_link(<<"SRC", libs)
#include <windows.h>
#include <winsock.h>
int main() { return 0; }
int t() { void ((*p)()); p = (void ((*)()))#{func}; return 0; }
SRC
      end
    else
      r = try_link(<<"SRC", libs)
int main() { return 0; }
int t() { #{func}(); return 0; }
SRC
    end
    unless r
      print "no\n"
      return false
    end
  else
    libs = append_library($libs, lib)
  end

  $libs = libs
  print "yes\n"
  return true
end

def find_library(lib, func, *paths)
  printf "checking for %s() in -l%s... ", func, lib
  STDOUT.flush

  libpath = $LIBPATH
  libs = append_library($libs, lib)
  until try_link(<<"SRC", libs)
int main() { return 0; }
int t() { #{func}(); return 0; }
SRC
    if paths.size == 0
      $LIBPATH = libpath
      print "no\n"
      return false
    end
    $LIBPATH = libpath | [paths.shift]
  end
  $libs = libs
  print "yes\n"
  return true
end

def have_func(func, header=nil)
  printf "checking for %s()... ", func
  STDOUT.flush

  libs = $libs
  src = 
    if /mswin32|mingw/ =~ RUBY_PLATFORM
      r = <<"SRC"
#include <windows.h>
#include <winsock.h>
SRC
    else
      ""
    end
  unless header.nil?
  src << <<"SRC"
#include <#{header}>
SRC
  end
  r = try_link(src + <<"SRC", libs)
int main() { return 0; }
int t() { #{func}(); return 0; }
SRC
  unless r
    r = try_link(src + <<"SRC", libs)
int main() { return 0; }
int t() { void ((*p)()); p = (void ((*)()))#{func}; return 0; }
SRC
  end
  unless r
    print "no\n"
    return false
  end
  $defs.push(format("-DHAVE_%s", func.upcase))
  print "yes\n"
  return true
end

def have_header(header)
  printf "checking for %s... ", header
  STDOUT.flush

  unless try_cpp(<<"SRC")
#include <#{header}>
SRC
    print "no\n"
    return false
  end
  header.tr!("a-z./\055", "A-Z___")
  $defs.push(format("-DHAVE_%s", header))
  print "yes\n"
  return true
end

def arg_config(config, default=nil)
  unless defined? $configure_args
    $configure_args = {}
    for arg in CONFIG["configure_args"].split + ARGV
      next unless /^--/ =~ arg
      arg, val = arg.split('=', 2)
      $configure_args[arg] = val || true
    end
  end
  $configure_args.fetch(config, default)
end

def with_config(config, default=nil)
  unless /^--with-/ =~ config
    config = '--with-' + config
  end
  arg_config(config, default)
end

def enable_config(config, default=nil)
  if arg_config("--enable-"+config, default)
    true
  elsif arg_config("--disable-"+config, false)
    false
  else
    default
  end
end

def create_header()
  print "creating extconf.h\n"
  STDOUT.flush
  if $defs.length > 0
    hfile = open("extconf.h", "w")
    for line in $defs
      line =~ /^-D(.*)/
      hfile.printf "#define %s 1\n", $1
    end
    hfile.close
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

def create_makefile(target, srcdir = File.dirname($0))
  save_libs = $libs.dup
  save_libpath = $LIBPATH.dup
  print "creating Makefile\n"
  rm_f "conftest*"
  STDOUT.flush
  if target.include?('/')
    target_prefix, target = File.split(target)
    target_prefix[0,0] = '/'
  else
    target_prefix = ""
  end
  if CONFIG["DLEXT"] == $OBJEXT
    libs = $libs.split
    for lib in libs
      lib.sub!(/-l(.*)/, '"lib\1.a"')
    end
    $defs.push(format("-DEXTLIB='%s'", libs.join(",")))
  end
  $DLDFLAGS = CONFIG["DLDFLAGS"]

  $libs = CONFIG["LIBRUBYARG"] + " " + $libs
  $configure_args['--enable-shared'] or $LIBPATH |= [$topdir]
  $LIBPATH |= [CONFIG["libdir"]]

  defflag = ''
  if RUBY_PLATFORM =~ /cygwin|mingw/
    deffile = target + '.def'
    if not File.exist? deffile
      if File.exist? File.join srcdir, deffile
	deffile = File.join srcdir, deffile
      else
        open(deffile, 'wb') do |f|
          f.print "EXPORTS\n", "Init_", target, "\n"
        end
      end
    end
    defflag = "--def=" + deffile
  end

  if RUBY_PLATFORM =~ /mswin32/
    libpath = $LIBPATH.join(';')
  else
    $LIBPATH.each {|d| $DLDFLAGS << " -L" << d}
    if /netbsdelf/ =~ RUBY_PLATFORM
      $LIBPATH.each {|d| $DLDFLAGS << " -Wl,-R" + d}
    end
  end
  drive = File::PATH_SEPARATOR == ';' ? /\A\w:/ : /\A/

  unless $objs then
    $objs = []
    for f in Dir[File.join(srcdir || ".", "*.{#{SRC_EXT.join(%q{,})}}")]
      f = File.basename(f)
      f.sub!(/(#{SRC_EXT.join(%q{|})})$/, $OBJEXT)
      $objs.push f
    end
  else
    for i in $objs
      i.sub!(/\.o\z/, ".#{$OBJEXT}")
    end
  end
  $objs = $objs.join(" ")

  mfile = open("Makefile", "w")
  mfile.binmode if /mingw/ =~ RUBY_PLATFORM
  mfile.print  <<EOMF
SHELL = /bin/sh

#### Start of system configuration section. ####

srcdir = #{srcdir || $srcdir}
topdir = #{$topdir}
hdrdir = #{$hdrdir}
VPATH = $(srcdir)

CC = #{CONFIG["CC"]}

CFLAGS   = #{CONFIG["CCDLFLAGS"]} #{CFLAGS} #{$CFLAGS}
CPPFLAGS = -I. -I$(hdrdir) -I$(srcdir) -I#{CONFIG["includedir"]} #{$defs.join(" ")} #{CONFIG["CPPFLAGS"]} #{$CPPFLAGS}
CXXFLAGS = $(CFLAGS)
DLDFLAGS = #{$DLDFLAGS} #{$LDFLAGS}
LDSHARED = #{CONFIG["LDSHARED"]} #{defflag}
LIBPATH = #{libpath}

RUBY_INSTALL_NAME = #{CONFIG["RUBY_INSTALL_NAME"]}
RUBY_SO_NAME = #{CONFIG["RUBY_SO_NAME"]}
arch = #{CONFIG["arch"]}
ruby_version = #{Config::CONFIG["ruby_version"]}
#{
if destdir = CONFIG["prefix"].scan(drive)[0] and !destdir.empty?
  "\nDESTDIR = " + destdir
else
  ""
end
}
prefix = #{with_destdir CONFIG["prefix"].sub(drive, '')}
exec_prefix = #{with_destdir CONFIG["exec_prefix"].sub(drive, '')}
libdir = #{with_destdir $libdir.sub(drive, '')}
rubylibdir = #{with_destdir $rubylibdir.sub(drive, '')}
archdir = #{with_destdir $archdir.sub(drive, '')}
sitedir = #{with_destdir $sitedir.sub(drive, '')}
sitelibdir = #{with_destdir $sitelibdir.sub(drive, '')}
sitearchdir = #{with_destdir $sitearchdir.sub(drive, '')}
target_prefix = #{target_prefix}

#### End of system configuration section. ####

LOCAL_LIBS = #{$LOCAL_LIBS} #{$local_flags}
LIBS = #{$libs}
OBJS = #{$objs}

TARGET = #{target}
DLLIB = $(TARGET).#{CONFIG["DLEXT"]}

RUBY = #{CONFIG["ruby_install_name"]}
RM = $(RUBY) -rftools -e "File::rm_f(*ARGV.map{|x|Dir[x]}.flatten.uniq)"

EXEEXT = #{CONFIG["EXEEXT"]}

all:		$(DLLIB)

clean:;		@$(RM) *.#{$OBJEXT} *.so *.sl *.a $(DLLIB)
		@$(RM) $(TARGET).lib $(TARGET).exp $(TARGET).ilk *.pdb $(CLEANFILES)

distclean:	clean
		@$(RM) Makefile extconf.h conftest.* mkmf.log
		@$(RM) core ruby$(EXEEXT) *~ $(DISTCLEANFILES)

realclean:	distclean

install:	$(archdir)$(target_prefix)/$(DLLIB)

site-install:	$(sitearchdir)$(target_prefix)/$(DLLIB)

$(archdir)$(target_prefix)/$(DLLIB): $(DLLIB)
	@$(RUBY) -r ftools -e 'File::makedirs(*ARGV)' $(rubylibdir) $(archdir)$(target_prefix)
	@$(RUBY) -r ftools -e 'File::install(ARGV[0], ARGV[1], 0555, true)' $(DLLIB) $(archdir)$(target_prefix)/$(DLLIB)
EOMF
  install_rb(mfile, "$(rubylibdir)$(target_prefix)", srcdir)
  mfile.printf "\n"

  mfile.printf <<EOMF
$(sitearchdir)$(target_prefix)/$(DLLIB): $(DLLIB)
	@$(RUBY) -r ftools -e 'File::makedirs(*ARGV)' $(sitearchdir)$(target_prefix)
	@$(RUBY) -r ftools -e 'File::install(ARGV[0], ARGV[1], 0555, true)' $(DLLIB) $(sitearchdir)$(target_prefix)/$(DLLIB)
EOMF
  install_rb(mfile, "$(sitelibdir)$(target_prefix)", srcdir)
  mfile.printf "\n"

  if /mswin32/ !~ RUBY_PLATFORM
    mfile.print "
.c.#{$OBJEXT}:
	$(CC) $(CFLAGS) $(CPPFLAGS) -c -o $@ $<

.cc.#{$OBJEXT}:
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -c -o $@ $<
.cpp.#{$OBJEXT}:
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -c -o $@ $<
.cxx.#{$OBJEXT}:
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -c -o $@ $<
.C.#{$OBJEXT}:
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -c -o $@ $<
"
  elsif /nmake/i =~ $make
    mfile.print "
{$(srcdir)}.c.#{$OBJEXT}:
	$(CC) $(CFLAGS) -I$(<D) $(CPPFLAGS) -c $(<:/=\\)
.c.#{$OBJEXT}:
	$(CC) $(CFLAGS) -I$(<D) $(CPPFLAGS) -c $(<:/=\\)

{$(srcdir)}.cc{}.#{$OBJEXT}:
	$(CXX) -I. -I$(<D) $(CXXFLAGS) $(CPPFLAGS) -c $(<:/=\\)
.cc.#{$OBJEXT}:
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -c $(<:/=\\)
{$(srcdir)}.cpp{}.#{$OBJEXT}:
	$(CXX) -I. -I$(<D) $(CXXFLAGS) $(CPPFLAGS) -c $(<:/=\\)
.cpp.#{$OBJEXT}:
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -c $(<:/=\\)
{$(srcdir)}.cxx{}.#{$OBJEXT}:
	$(CXX) -I. -I$(<D) $(CXXFLAGS) $(CPPFLAGS) -c $(<:/=\\)
.cxx.#{$OBJEXT}:
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -c $(<:/=\\)
"
  else
    mfile.print "
.SUFFIXES: .#{$OBJEXT}

.c.#{$OBJEXT}:
	$(CC) $(CFLAGS) $(CPPFLAGS) -c $(subst /,\\\\,$<)

.cc.#{$OBJEXT} .cpp.#{$OBJEXT} .cxx.#{$OBJEXT} .C.#{$OBJEXT}:
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -c $(subst /,\\\\,$<)
"
  end

  if CONFIG["DLEXT"] != $OBJEXT
    mfile.print "$(DLLIB): $(OBJS)\n"
    if /mswin32/ =~ RUBY_PLATFORM
      if /nmake/i =~ $make
	mfile.print "\tset LIB=$(LIBPATH:/=\\);$(LIB)\n"
      else
	mfile.print "\tenv LIB='$(subst /,\\\\,$(LIBPATH));$(LIB)' \\\n"
      end
    end
    mfile.print "\t$(LDSHARED) $(DLDFLAGS) #{OUTFLAG}$(DLLIB) $(OBJS) $(LIBS) $(LOCAL_LIBS)\n"
  elsif not File.exist?(target + ".c") and not File.exist?(target + ".cc")
    mfile.print "$(DLLIB): $(OBJS)\n"
    case RUBY_PLATFORM
    when "m68k-human"
      mfile.printf "ar cru $(DLLIB) $(OBJS)\n"
    else
      mfile.printf "ld $(DLDFLAGS) -r -o $(DLLIB) $(OBJS)\n"
    end
  end

  depend = File.join(srcdir, "depend")
  if File.exist?(depend)
    dfile = open(depend, "r")
    mfile.printf "###\n"
    while line = dfile.gets()
      mfile.printf "%s", line.gsub(/\.o\b/, ".#{$OBJEXT}")
    end
    dfile.close
  end
  mfile.close
  $libs = save_libs
  $LIBPATH = save_libpath
end

$OBJEXT = CONFIG["OBJEXT"]
$objs = nil
$libs = CONFIG["DLDLIBS"]
$local_flags = ""
case RUBY_PLATFORM
when /mswin32/
  $local_flags = "-link /INCREMENTAL:no /EXPORT:Init_$(TARGET)"
end
$LOCAL_LIBS = ""
$defs = []

$make = with_config("make-prog", ENV["MAKE"] || "make")

$CFLAGS = with_config("cflags", "")
$CPPFLAGS = with_config("cppflags", "")
$LDFLAGS = with_config("ldflags", "")
$LIBPATH = []

dir_config("opt")
