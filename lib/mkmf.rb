# module to create Makefile for extension modules
# invoke like: ruby -r mkmf extconf.rb

require 'rbconfig'
require 'find'

include Config

$found = false;
$lib_cache = {}
$lib_found = {}
$func_cache = {}
$func_found = {}
$hdr_cache = {}
$hdr_found = {}

$config_cache = CONFIG["compile_dir"]+"/ext/config.cache"
if File.exist?($config_cache) then
  f = open($config_cache, "r")
  while f.gets
    case $_
    when /^lib: (.+) (yes|no)/
      $lib_cache[$1] = $2
    when /^func: ([\w_]+) (yes|no)/
      $func_cache[$1] = $2
    when /^hdr: (.+) (yes|no)/
      $hdr_cache[$1] = $2
    end
  end
  f.close
end

$srcdir = CONFIG["srcdir"]
$libdir = CONFIG["libdir"]+"/ruby/"+CONFIG["MAJOR"]+"."+CONFIG["MINOR"]
$archdir = $libdir+"/"+CONFIG["arch"]
$install = CONFIG["INSTALL_PROGRAM"]
$install_dllib = CONFIG["INSTALL_DLLIB"]
$install_data = CONFIG["INSTALL_DATA"]
if $install =~ %r!^[^\s/]+/! then
  $install = CONFIG["compile_dir"]+"/"+$install
  $install_dllib = CONFIG["compile_dir"]+"/"+$install_dllib
  $install_data = CONFIG["compile_dir"]+"/"+$install_data
end

if File.exist? $archdir + "/ruby.h"
  $hdrdir = $archdir
elsif File.exist? $srcdir + "/ruby.h"
  $hdrdir = $srcdir
else
  STDERR.print "can't find header files for ruby.\n"
  exit 1
end

CFLAGS = CONFIG["CFLAGS"]
if PLATFORM == "m68k-human"
  CFLAGS.gsub!(/-c..-stack=[0-9]+ */, '')
elsif PLATFORM =~ /-nextstep|-rhapsody/
  CFLAGS.gsub!( /-arch\s\w*/, '' );
end
if /win32|djgpp|mingw32|m68k-human|i386-os2_emx/i =~ PLATFORM
  $null = open("nul", "w")
else
  $null = open("/dev/null", "w")
end
LINK = "#{CONFIG['CC']} -o conftest -I#{$hdrdir} -I#{CONFIG['includedir']} #{CFLAGS} %s #{CONFIG['LDFLAGS']} %s conftest.c %s %s #{CONFIG['LIBS']}"
CPP = "#{CONFIG['CPP']} -E -I#{$hdrdir} -I#{CONFIG['includedir']} #{CFLAGS} %s %s conftest.c"

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

def install_rb(mfile)
  path = []
  dir = []
  Find.find("lib") do |f|
    next unless /\.rb$/ =~ f
    f = f[4..-1]
    path.push f
    dir |= File.dirname(f)
  end
  for f in dir
    next if f == "."
    mfile.printf "\t@test -d $(libdir)/%s || mkdir $(libdir)/%s\n", f, f
  end
  for f in path
    mfile.printf "\t$(INSTALL_DATA) lib/%s $(libdir)/%s\n", f, f
  end
end

def have_library(lib, func="main")
  printf "checking for %s() in -l%s... ", func, lib
  STDOUT.flush
  if $lib_cache[lib]
    if $lib_cache[lib] == "yes"
      if $libs
        $libs = "-l" + lib + " " + $libs 
      else
	$libs = "-l" + lib
      end
      print "(cached) yes\n"
      return TRUE
    else
      print "(cached) no\n"
      return FALSE
    end
  end

  if func && func != ""
    cfile = open("conftest.c", "w")
    cfile.printf "\
int main() { return 0; }
int t() { %s(); return 0; }
", func
    cfile.close

    if $libs
      libs = "-l" + lib + " " + $libs 
    else
      libs = "-l" + lib
    end
    unless try_link(<<"SRC", libs)
int main() { return 0; }
int t() { #{func}(); return 0; }
SRC
      $lib_cache[lib] = 'no'
      $cache_mod = TRUE
      print "no\n"
      return FALSE
    end
  else
    if $libs
      libs = "-l" + lib + " " + $libs 
    else
      libs = "-l" + lib
    end
  end

  $libs = libs
  $lib_cache[lib] = 'yes'
  $cache_mod = TRUE
  print "yes\n"
  return TRUE
end

def have_func(func)
  printf "checking for %s()... ", func
  STDOUT.flush
  if $func_cache[func]
    if $func_cache[func] == "yes"
      $defs.push(format("-DHAVE_%s", func.upcase))
      print "(cached) yes\n"
      return TRUE
    else
      print "(cached) no\n"
      return FALSE
    end
  end

  libs = $libs
  libs = "" if libs == nil

  unless try_link(<<"SRC", libs)
char #{func}();
int main() { return 0; }
int t() { #{func}(); return 0; }
SRC
    $func_found[func] = 'no'
    $found = TRUE
    print "no\n"
    return FALSE
  end
  $defs.push(format("-DHAVE_%s", func.upcase))
  $func_found[func] = 'yes'
  $found = TRUE
  print "yes\n"
  return TRUE
end

def have_header(header)
  printf "checking for %s... ", header
  STDOUT.flush
  if $hdr_cache[header]
    if $hdr_cache[header] == "yes"
      header.tr!("a-z./\055", "A-Z___")
      $defs.push(format("-DHAVE_%s", header))
      print "(cached) yes\n"
      return TRUE
    else
      print "(cached) no\n"
      return FALSE
    end
  end

  unless try_cpp(<<"SRC")
#include <#{header}>
SRC
    $hdr_found[header] = 'no'
    $found = TRUE
    print "no\n"
    return FALSE
  end
  $hdr_found[header] = 'yes'
  header.tr!("a-z./\055", "A-Z___")
  $defs.push(format("-DHAVE_%s", header))
  $found = TRUE
  print "yes\n"
  return TRUE
end

def arg_config(config, default=nil)
  return default if /mswin32/i =~ PLATFORM
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

def create_makefile(target)
  print "creating Makefile\n"
  system "rm -f conftest*"
  STDOUT.flush
  if $libs and CONFIG["DLEXT"] == "o"
    libs = $libs.split
    for lib in libs
      lib.sub!(/-l(.*)/, '"lib\1.a"')
    end
    $defs.push(format("-DEXTLIB='%s'", libs.join(",")))
  end
  $libs = "" unless $libs
  $DLDFLAGS = CONFIG["DLDFLAGS"]

  if PLATFORM =~ /beos/
    $libs = $libs + " -lruby"
    $DLDFLAGS = $DLDFLAGS + " -L" + CONFIG["prefix"] + "/lib"
  end

  unless $objs then
    $objs = Dir["*.{c,cc,m}"]
    for f in $objs
      f.sub!(/\.(c|cc|m)$/, ".o")
    end
  end
  $objs = $objs.join(" ")

  mfile = open("Makefile", "w")
  mfile.print  <<EOMF
SHELL = /bin/sh

#### Start of system configuration section. ####

srcdir = #{$srcdir}
topdir = #{$hdrdir}
hdrdir = #{$hdrdir}

CC = #{CONFIG["CC"]}

CFLAGS   = #{CONFIG["CCDLFLAGS"]} -I$(hdrdir) -I#{CONFIG["includedir"]} #{CFLAGS} #{$CFLAGS} #{$defs.join(" ")}
CXXFLAGS = $(CFLAGS)
DLDFLAGS = #{$DLDFLAGS} #{$LDFLAGS}
LDSHARED = #{CONFIG["LDSHARED"]}

prefix = #{CONFIG["prefix"]}
exec_prefix = #{CONFIG["exec_prefix"]}
libdir = #{$libdir}
archdir = #{$archdir}

#### End of system configuration section. ####

LOCAL_LIBS = #{$LOCAL_LIBS}
LIBS = #{$libs}
OBJS = #{$objs}

TARGET = #{target}
DLLIB = $(TARGET).#{CONFIG["DLEXT"]}

INSTALL = #{$install}
INSTALL_DLLIB = #{$install_dllib}
INSTALL_DATA = #{$install_data}

binsuffix = #{CONFIG["binsuffix"]}

all:		$(DLLIB)

clean:;		@rm -f *.o *.so *.sl *.a
		@rm -f Makefile extconf.h conftest.*
		@rm -f core ruby$(binsuffix) *~

realclean:	clean

install:	$(archdir)/$(DLLIB)

$(archdir)/$(DLLIB): $(DLLIB)
	@test -d $(libdir) || mkdir $(libdir)
	@test -d $(archdir) || mkdir $(archdir)
	$(INSTALL_DLLIB) $(DLLIB) $(archdir)/$(DLLIB)
EOMF
  install_rb(mfile)
  mfile.printf "\n"

  if CONFIG["DLEXT"] != "o"
    mfile.printf <<EOMF
$(DLLIB): $(OBJS)
	$(LDSHARED) $(DLDFLAGS) -o $(DLLIB) $(OBJS) $(LIBS) $(LOCAL_LIBS)
EOMF
  elsif not File.exist?(target + ".c") and not File.exist?(target + ".cc")
    mfile.print "$(DLLIB): $(OBJS)\n"
    case PLATFORM
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
      mfile.print line
    end
    dfile.close
  end
  mfile.close

  if $found
    begin
      f = open($config_cache, "w")
      for k,v in $lib_cache
	f.printf "lib: %s %s\n", k, v.downcase
      end
      for k,v in $lib_found
	f.printf "lib: %s %s\n", k, v.downcase
      end
      for k,v in $func_cache
	f.printf "func: %s %s\n", k, v.downcase
      end
      for k,v in $func_found
	f.printf "func: %s %s\n", k, v.downcase
      end
      for k,v in $hdr_cache
	f.printf "hdr: %s %s\n", k, v.downcase
      end
      for k,v in $hdr_found
	f.printf "hdr: %s %s\n", k, v.downcase
      end
      f.close
    rescue
    end
  end
  
  if PLATFORM =~ /beos/
    print "creating ruby.def\n"
    open("ruby.def", "w") do |file|
      file.print("EXPORTS\n") if PLATFORM =~ /^i/
      file.print("Init_#{target}\n")
    end
  end
end

$libs = PLATFORM =~ /cygwin32|beos|rhapsody|nextstep/ ? nil : "-lc"
$objs = nil
$LOCAL_LIBS = ""
$CFLAGS = ""
$LDFLAGS = ""
$defs = []
