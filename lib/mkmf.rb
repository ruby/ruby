# module to create Makefile for extension modules
# invoke like: ruby -r mkmf extconf.rb

require 'rbconfig'
require 'find'

include Config

SRC_EXT = ["c", "cc", "m", "cxx", "cpp", "C"]

$config_cache = CONFIG["compile_dir"]+"/ext/config.cache"

$srcdir = CONFIG["srcdir"]
$libdir = CONFIG["libdir"]+"/ruby/"+CONFIG["MAJOR"]+"."+CONFIG["MINOR"]
$archdir = $libdir+"/"+CONFIG["arch"]
$sitelibdir = CONFIG["sitedir"]+"/"+CONFIG["MAJOR"]+"."+CONFIG["MINOR"]
$sitearchdir = $sitelibdir+"/"+CONFIG["arch"]

if File.exist? $archdir + "/ruby.h"
  $hdrdir = $archdir
elsif File.exist? $srcdir + "/ruby.h"
  $hdrdir = $srcdir
else
  STDERR.print "can't find header files for ruby.\n"
  exit 1
end
$topdir = $hdrdir
$hdrdir.gsub!('/', '\\') if RUBY_PLATFORM =~ /mswin32/

CFLAGS = CONFIG["CFLAGS"]
if RUBY_PLATFORM == "m68k-human"
  CFLAGS.gsub!(/-c..-stack=[0-9]+ */, '')
elsif RUBY_PLATFORM =~ /-nextstep|-rhapsody/
  CFLAGS.gsub!( /-arch\s\w*/, '' )
end
if /win32|djgpp|mingw32|m68k-human|i386-os2_emx/i =~ RUBY_PLATFORM
  $null = open("nul", "w")
else
  $null = open("/dev/null", "w")
end
LINK = "#{CONFIG['CC']} -o conftest -I#{$hdrdir} #{CFLAGS} -I#{CONFIG['includedir']} %s #{CONFIG['LDFLAGS']} %s conftest.c %s %s #{CONFIG['LIBS']}"
CPP = "#{CONFIG['CPP']} -E -I#{$hdrdir} #{CFLAGS} -I#{CONFIG['includedir']} %s %s conftest.c"

$orgerr = $stderr.dup
$orgout = $stdout.dup
def xsystem command
  if $DEBUG
    print command, "\n"
    return system(command)
  end
  $stderr.reopen($null) 
  $stdout.reopen($null) 
  r = system(command)
  $stderr.reopen($orgerr)
  $stdout.reopen($orgout)
  return r
end

def try_link0(src, opt="")
  cfile = open("conftest.c", "w")
  cfile.print src
  cfile.close
  xsystem(format(LINK, $CFLAGS, $LDFLAGS, opt, $LOCAL_LIBS))
end

def try_link(src, opt="")
  begin
    try_link0(src, opt)
  ensure
    system "rm -f conftest*"
  end
end

def try_cpp(src, opt="")
  cfile = open("conftest.c", "w")
  cfile.print src
  cfile.close
  begin
    xsystem(format(CPP, $CFLAGS, opt))
  ensure
    system "rm -f conftest*"
  end
end

def egrep_cpp(pat, src, opt="")
  cfile = open("conftest.c", "w")
  cfile.print src
  cfile.close
  begin
    xsystem(format(CPP+"|egrep #{pat}", $CFLAGS, opt))
  ensure
    system "rm -f conftest*"
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
    system "rm -f conftest*"
  end
end

def install_rb(mfile, dest, srcdir = nil)
  libdir = "lib"
  libdir = srcdir + "/" + libdir if srcdir
  path = []
  dir = []
  Find.find(libdir) do |f|
    next unless /\.rb$/ =~ f
    f = f[libdir.length+1..-1]
    path.push f
    dir |= File.dirname(f)
  end
  for f in dir
    next if f == "."
    mfile.printf "\t@$(RUBY) -r ftools -e 'File::makedirs(*ARGV)' %s/%s\n", dest, f
  end
  for f in path
    mfile.printf "\t@$(RUBY) -r ftools -e 'File::install(ARGV[0], ARGV[1], 0644, true)' lib/%s %s/%s\n", f, dest, f
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
    if /mswin32/ =~ RUBY_PLATFORM
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

  ldflags = $LDFLAGS
  libs = append_library($libs, lib)
  until try_link(<<"SRC", libs)
int main() { return 0; }
int t() { #{func}(); return 0; }
SRC
    if paths.size == 0
      $LDFLAGS = ldflags
      print "no\n"
      return false
    end
    $LDFLAGS = ldflags + " -L"+paths.shift
  end
  $libs = libs
  print "yes\n"
  return true
end

def have_func(func)
  printf "checking for %s()... ", func
  STDOUT.flush

  libs = $libs

  if /mswin32/ =~ RUBY_PLATFORM
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
  header.tr!("a-z\055./", "A-Z___")
  $defs.push(format("-DHAVE_%s", header))
  print "yes\n"
  return true
end

def arg_config(config, default=nil)
  unless defined? $configure_args
    $configure_args = {}
    for arg in CONFIG["configure_args"].split + ARGV
      next unless /^--/ =~ arg
      if /=/ =~ arg
	$configure_args[$`] = $'
      else
	$configure_args[arg] = true
      end
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

def dir_config(target)
  dir = with_config("%s-dir"%target)
  if dir
    idir = " -I"+dir+"/include"
    ldir = " -L"+dir+"/lib"
  end
  unless idir
    dir = with_config("%s-include"%target)
    idir = " -I"+dir if dir
  end
  unless ldir
    dir = with_config("%s-lib"%target)
    ldir = " -L"+dir if dir
  end

  $CFLAGS += idir if idir
  $LDFLAGS += ldir if ldir
end

def create_makefile(target)
  print "creating Makefile\n"
  system "rm -f conftest*"
  STDOUT.flush
  if CONFIG["DLEXT"] == $OBJEXT
    libs = $libs.split
    for lib in libs
      lib.sub!(/-l(.*)/, '"lib\1.a"')
    end
    $defs.push(format("-DEXTLIB='%s'", libs.join(",")))
  end
  $DLDFLAGS = CONFIG["DLDFLAGS"]

  if RUBY_PLATFORM =~ /beos/
    $libs = $libs + " " + CONFIG["LIBRUBYARG"]
    $DLDFLAGS = $DLDFLAGS + " -L" + CONFIG["prefix"] + "/lib"
  end

  defflag = ''
  if RUBY_PLATFORM =~ /cygwin/
    if File.exist? target + ".def"
      defflag = "--def=" + target + ".def"
    end
    $libs = $libs + " " + CONFIG["LIBRUBYARG"]
    $DLDFLAGS = $DLDFLAGS + " -L$(topdir)"
  end

  unless $objs then
    $objs = []
    for f in Dir["*.{#{SRC_EXT.join(%q{,})}}"]
      f = File.basename(f)
      f.sub!(/(#{SRC_EXT.join(%q{|})})$/, $OBJEXT)
      $objs.push f
    end
  end
  $objs = $objs.join(" ")

  mfile = open("Makefile", "w")
  mfile.print  <<EOMF
SHELL = /bin/sh

#### Start of system configuration section. ####

srcdir = #{$srcdir}
topdir = #{$topdir}
hdrdir = #{$hdrdir}

CC = #{CONFIG["CC"]}

CFLAGS   = #{CONFIG["CCDLFLAGS"]} -I$(hdrdir) #{CFLAGS} #{$CFLAGS} -I#{CONFIG["includedir"]} #{$defs.join(" ")}
CXXFLAGS = $(CFLAGS)
DLDFLAGS = #{$DLDFLAGS} #{$LDFLAGS}
LDSHARED = #{CONFIG["LDSHARED"]} #{defflag}

RUBY_INSTALL_NAME = #{CONFIG["RUBY_INSTALL_NAME"]}

prefix = #{CONFIG["prefix"]}
exec_prefix = #{CONFIG["exec_prefix"]}
libdir = #{$libdir}
archdir = #{$archdir}
sitelibdir = #{$sitelibdir}
sitearchdir = #{$sitearchdir}

#### End of system configuration section. ####

LOCAL_LIBS = #{$LOCAL_LIBS} #{$local_flags}
LIBS = #{$libs}
OBJS = #{$objs}

TARGET = #{target}
DLLIB = $(TARGET).#{CONFIG["DLEXT"]}

RUBY = #{CONFIG["ruby_install_name"]}

EXEEXT = #{CONFIG["EXEEXT"]}

all:		$(DLLIB)

clean:;		@rm -f *.#{$OBJEXT} *.so *.sl *.a $(DLLIB)
		@rm -f $(TARGET).lib $(TARGET).exp
		@rm -f Makefile extconf.h conftest.*
		@rm -f core ruby$(EXEEXT) *~

realclean:	clean

install:	$(archdir)/$(DLLIB)

site-install:	$(sitearchdir)/$(DLLIB)

$(archdir)/$(DLLIB): $(DLLIB)
	@$(RUBY) -r ftools -e 'File::makedirs(*ARGV)' $(libdir) $(archdir)
	@$(RUBY) -r ftools -e 'File::install(ARGV[0], ARGV[1], 0555, true)' $(DLLIB) $(archdir)/$(DLLIB)
EOMF
  install_rb(mfile, "$(libdir)")
  mfile.printf "\n"

  mfile.printf <<EOMF
$(sitearchdir)/$(DLLIB): $(DLLIB)
	@$(RUBY) -r ftools -e 'File::makedirs(*ARGV)' $(libdir) $(sitearchdir)
	@$(RUBY) -r ftools -e 'File::install(ARGV[0], ARGV[1], 0555, true)' $(DLLIB) $(sitearchdir)/$(DLLIB)
EOMF
  install_rb(mfile, "$(sitelibdir)")
  mfile.printf "\n"

  if CONFIG["DLEXT"] != $OBJEXT
    mfile.printf <<EOMF
$(DLLIB): $(OBJS)
	$(LDSHARED) $(DLDFLAGS) -o $(DLLIB) $(OBJS) $(LIBS) $(LOCAL_LIBS)
EOMF
  elsif not File.exist?(target + ".c") and not File.exist?(target + ".cc")
    mfile.print "$(DLLIB): $(OBJS)\n"
    case RUBY_PLATFORM
    when "m68k-human"
      mfile.printf "ar cru $(DLLIB) $(OBJS)\n"
    else
      mfile.printf "ld $(DLDFLAGS) -r -o $(DLLIB) $(OBJS)\n"
    end
  end

  if File.exist?("depend")
    dfile = open("depend", "r")
    mfile.printf "###\n"
    while line = dfile.gets()
      mfile.printf "%s", line.gsub(/\.o/, ".#{$OBJEXT}")
    end
    dfile.close
  end
  mfile.close

  if RUBY_PLATFORM =~ /beos/
    if RUBY_PLATFORM =~ /^powerpc/ then
      deffilename = "ruby.exp"
    else
      deffilename = "ruby.def"
    end
    print "creating #{deffilename}\n"
    open(deffilename, "w") do |file|
      file.print("EXPORTS\n") if RUBY_PLATFORM =~ /^i/
      file.print("Init_#{target}\n")
    end
  end
end

$OBJEXT = CONFIG["OBJEXT"]
$objs = nil
$libs = "-lc"
$local_flags = ""
case RUBY_PLATFORM
when /cygwin|beos|openstep|nextstep|rhapsody/
  $libs = ""
when /mswin32/
  $libs = ""
  $local_flags = "rubymw.lib -link /LIBPATH:$(topdir) /EXPORT:Init_$(TARGET)"
end
$LOCAL_LIBS = ""
$defs = []

dir = with_config("opt-dir")
if dir
  idir = "-I"+dir+"/include"
  ldir = "-L"+dir+"/lib"
end
unless idir
  dir = with_config("opt-include")
  idir = "-I"+dir if dir
end
unless ldir
  dir = with_config("opt-lib")
  ldir = "-L"+dir if dir
end

$CFLAGS = idir || ""
$LDFLAGS = ldir || ""
