# module to create Makefile for extension modules
# invoke like: ruby -r mkmf extconf.rb

require 'rbconfig'
require 'find'

include Config

$cache_mod = false
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

if File.exist? $archdir + "/ruby.h"
  $hdrdir = $archdir
elsif File.exist? $srcdir + "/ruby.h"
  $hdrdir = $srcdir
else
  STDERR.print "can't find header files for ruby.\n"
  exit 1
end

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

def install_rb(mfile, srcdir = nil)
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
    mfile.printf "\t@$(RUBY) -r ftools -e 'File::makedirs(*ARGV)' $(libdir)/%s\n", f
  end
  for f in path
    mfile.printf "\t@$(RUBY) -r ftools -e 'File::install(ARGV[0], ARGV[1], 0644, true)' lib/%s $(libdir)/%s\n", f, f
  end
end

def have_library(lib, func="main")
  printf "checking for %s() in -l%s... ", func, lib
  STDOUT.flush
  if $lib_cache[lib]
    if $lib_cache[lib] == "yes"
      $libs = "-l" + lib + " " + $libs 
      print "(cached) yes\n"
      return true
    else
      print "(cached) no\n"
      return false
    end
  end

  if func && func != ""
    libs = "-l" + lib + " " + $libs 
    unless try_link(<<"SRC", libs)
int main() { return 0; }
int t() { #{func}(); return 0; }
SRC
      $lib_cache[lib] = 'no'
      $cache_mod = true
      print "no\n"
      return false
    end
  else
    libs = "-l" + lib + " " + $libs 
  end

  $libs = libs
  $lib_cache[lib] = 'yes'
  $cache_mod = true
  print "yes\n"
  return true
end

def have_func(func)
  printf "checking for %s()... ", func
  STDOUT.flush
  if $func_cache[func]
    if $func_cache[func] == "yes"
      $defs.push(format("-DHAVE_%s", func.upcase))
      print "(cached) yes\n"
      return true
    else
      print "(cached) no\n"
      return false
    end
  end

  libs = $libs

  unless try_link(<<"SRC", libs)
char #{func}();
int main() { return 0; }
int t() { #{func}(); return 0; }
SRC
    $func_found[func] = 'no'
    $cache_mod = true
    print "no\n"
    return false
  end
  $defs.push(format("-DHAVE_%s", func.upcase))
  $func_found[func] = 'yes'
  $cache_mod = true
  print "yes\n"
  return true
end

def have_header(header)
  printf "checking for %s... ", header
  STDOUT.flush
  if $hdr_cache[header]
    if $hdr_cache[header] == "yes"
      header.tr!("a-z./\055", "A-Z___")
      $defs.push(format("-DHAVE_%s", header))
      print "(cached) yes\n"
      return true
    else
      print "(cached) no\n"
      return false
    end
  end

  unless try_cpp(<<"SRC")
#include <#{header}>
SRC
    $hdr_found[header] = 'no'
    $cache_mod = true
    print "no\n"
    return false
  end
  $hdr_found[header] = 'yes'
  header.tr!("a-z./\055", "A-Z___")
  $defs.push(format("-DHAVE_%s", header))
  $cache_mod = true
  print "yes\n"
  return true
end

def arg_config(config, default=nil)
  return default if /mswin32/i =~ RUBY_PLATFORM
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

def create_makefile(target, installpos = "")
  print "creating Makefile\n"
  system "rm -f conftest*"
  STDOUT.flush
  if CONFIG["DLEXT"] == "o"
    libs = $libs.split
    for lib in libs
      lib.sub!(/-l(.*)/, '"lib\1.a"')
    end
    $defs.push(format("-DEXTLIB='%s'", libs.join(",")))
  end
  $DLDFLAGS = CONFIG["DLDFLAGS"]

  if RUBY_PLATFORM =~ /beos/
    $libs = $libs + " -lruby"
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
LDSHARED = #{CONFIG["LDSHARED"]} #{defflag}

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

RUBY = #{CONFIG["ruby_install_name"]}

binsuffix = #{CONFIG["binsuffix"]}

all:		$(DLLIB)

clean:;		@rm -f *.o *.so *.sl *.a $(DLLIB)
		@rm -f Makefile extconf.h conftest.*
		@rm -f core ruby$(binsuffix) *~

realclean:	clean

install:	$(archdir)/$(DLLIB)

$(archdir)/$(DLLIB): $(DLLIB)
	@$(RUBY) -r ftools -e 'File::makedirs(*ARGV)' $(libdir) $(archdir)
	@$(RUBY) -r ftools -e 'File::install(ARGV[0], ARGV[1], 0555, true)' $(DLLIB) $(archdir)/$(DLLIB)
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
      mfile.print line
    end
    dfile.close
  end
  mfile.close

  if $cache_mod
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

$libs = RUBY_PLATFORM =~ /cygwin|beos|openstep|nextstep|rhapsody/ ? "" : "-lc"
$objs = nil
$LOCAL_LIBS = ""
$CFLAGS = ""
$LDFLAGS = ""
$defs = []
