#! /usr/local/bin/ruby
# -*- ruby -*-

$force_static = nil
$install = nil
$destdir = nil
$clean = nil
$nodynamic = nil
$extinit = nil
$extobjs = nil

if ARGV[0] == 'static'
  $force_static = true
  ARGV.shift
elsif ARGV[0] == 'install'
  $install = true
  $destdir = ARGV[1] || ''
  ARGV.shift
elsif ARGV[0] == 'clean'
  $clean = "clean"
  ARGV.shift
elsif ARGV[0] == 'distclean'
  $clean = "distclean"
  ARGV.shift
elsif ARGV[0] == 'realclean'
  $clean = "realclean"
  ARGV.shift
end

$extlist = []

$:.replace ["."]
require 'rbconfig'

srcdir = Config::CONFIG["srcdir"]

$:.replace [srcdir, srcdir+"/lib", "."]

require 'mkmf'
require 'find'
require 'ftools'
require 'shellwords'

$topdir = File.expand_path(".")
$top_srcdir = srcdir

Object.class_eval do remove_method :create_makefile end

def create_makefile(target)
  $target = target
  if target.include?('/')
    target_prefix, target = File.split(target)
    target_prefix[0,0] = '/'
  else
    target_prefix = ""
  end
  rm_f "conftest*"
  if CONFIG["DLEXT"] == $OBJEXT
    libs = $libs.split
    for lib in libs
      lib.sub!(/-l(.*)/, %%"lib\\1.#{$LIBEXT}"%)
    end
    $defs.push(format("-DEXTLIB='%s'", libs.join(",")))
  end

  $DLDFLAGS = CONFIG["DLDFLAGS"].dup

  if $configure_args['--enable-shared'] or CONFIG["LIBRUBY"] != CONFIG["LIBRUBY_A"]
    $libs = CONFIG["LIBRUBYARG"] + " " + $libs
    $LIBPATH.unshift $topdir
  end

  defflag = ''
  if RUBY_PLATFORM =~ /cygwin|mingw/ and not $static
    if not File.exist? target + '.def'
      open(target + '.def', 'wb') do |f|
        f.print "EXPORTS\n", "Init_", target, "\n"
      end
    end
    defflag = target + ".def"
  elsif RUBY_PLATFORM =~ /bccwin32/
    deffile = target + '.def'
    if not File.exist? target + '.def'
      open(deffile, 'wb') do |f|
        f.print "EXPORTS\n", "_Init_", target, "\n"
      end
    end
  end

  if RUBY_PLATFORM =~ /mswin32|bccwin32/
    libpath = $LIBPATH.join(';')
  else
    $LIBPATH.each {|d| $DLDFLAGS << " -L" << d}
    if /netbsdelf/ =~ RUBY_PLATFORM
      $LIBPATH.each {|d| $DLDFLAGS << " -Wl,-R" + d unless d == $topdir}
    end
  end

  $srcdir = File.join($top_srcdir,"ext",$mdir)
  mfile = open("Makefile", "w")
  mfile.binmode if /mingw/ =~ RUBY_PLATFORM
  mfile.printf <<EOL, if $static then "" else CONFIG["CCDLFLAGS"] end, $defs.join(" ")
SHELL = /bin/sh

#### Start of system configuration section. ####

srcdir = #{$srcdir}
VPATH = #{$srcdir}

topdir = #{$topdir}
hdrdir = #{$top_srcdir}

CC = #{CONFIG['CC']}

CFLAGS   = %s #{CFLAGS} #$CFLAGS
CPPFLAGS = -I$(topdir) -I$(hdrdir) %s #$CPPFLAGS
#{
if /bccwin32/ =~ RUBY_PLATFORM
  "DLDFLAGS = #$LDFLAGS -L" + '"$(libdir:/=\\);$(topdir:/=\\)"' + "\n" +
  "LDSHARED = #{CONFIG['LDSHARED']}\n"
else
  "DLDFLAGS = #$DLDFLAGS #$LDFLAGS\n" +
  "LDSHARED = #{CONFIG['LDSHARED']} #{defflag}\n"
end
}
EOL
  mfile.puts "LIBPATH = #{libpath}" if libpath

  mfile.puts ".SUFFIXES: .#{CONFIG['OBJEXT']}" unless #{CONFIG['OBJEXT']} == "o"

  mfile.printf "\

RUBY_INSTALL_NAME = #{CONFIG['RUBY_INSTALL_NAME']}
RUBY_SO_NAME = #{CONFIG['RUBY_SO_NAME']}
ruby_version = #{Config::CONFIG["ruby_version"]}

prefix = #{CONFIG['prefix']}
exec_prefix = #{CONFIG['exec_prefix']}
libdir = #{CONFIG['libdir']}
rubylibdir = $(libdir)/ruby/$(ruby_version)
#pkglibdir = $(libdir)/$(RUBY_INSTALL_NAME)/#{CONFIG['MAJOR']}.#{CONFIG['MINOR']}
pkglibdir = $(libdir)/ruby/#{CONFIG['MAJOR']}.#{CONFIG['MINOR']}
archdir = $(pkglibdir)/#{CONFIG['arch']}
target_prefix = #{target_prefix}
#{CONFIG['SET_MAKE']}

#### End of system configuration section. ####

"
  mfile.printf "LOCAL_LIBS = %s %s\n", $LOCAL_LIBS, $local_flags
  if /bccwin32/ =~ RUBY_PLATFORM
    mfile.printf "LIBS = $(topdir:/=\\)\\%s\n", $libs
  else
    mfile.printf "LIBS = %s\n", $libs
  end
  mfile.printf "OBJS = "
  if !$objs or (/bccwin32/ =~ RUBY_PLATFORM) then
    $objs = []
    for f in Dir["#{$top_srcdir}/ext/#{$mdir}/*.{#{SRC_EXT.join(%q{,})}}"]
      f = File.basename(f)
      f.sub!(/(#{SRC_EXT.join(%q{|})})$/, $OBJEXT)
      $objs.push f
    end
  else
    for i in $objs
      i.sub!(/\.o\z/, ".#{$OBJEXT}")
    end
  end
  mfile.printf $objs.join(" ")
  mfile.printf "\n"

  if /bccwin32/ =~ RUBY_PLATFORM
    ruby_interpreter = '$(topdir:/=\)/miniruby' + CONFIG['EXEEXT']
  else
    ruby_interpreter = "$(topdir)/miniruby" + CONFIG['EXEEXT']
    if /nmake/i =~ $make
      ruby_interpreter = '$(topdir:/=\)\miniruby' + CONFIG['EXEEXT']
    end
  end
  if defined? CROSS_COMPILING
    ruby_interpreter = CONFIG['MINIRUBY']
  end

  mfile.printf <<EOS
TARGET = #{target}
DLLIB = $(TARGET).#{$static ? $LIBEXT : CONFIG['DLEXT']}

RUBY = #{ruby_interpreter} -I$(topdir) -I$(hdrdir)/lib
RM = $(RUBY) -rftools -e "File::rm_f(*ARGV.map do|x|Dir[x]end.flatten.uniq)"
MAKEDIRS = $(RUBY) -r ftools -e 'File::makedirs(*ARGV)'
INSTALL_PROG = $(RUBY) -r ftools -e 'File::install(ARGV[0], ARGV[1], 0555, true)'
INSTALL_DATA = $(RUBY) -r ftools -e 'File::install(ARGV[0], ARGV[1], 0644, true)'

EXEEXT = CONFIG['EXEEXT']

all:		$(DLLIB)

clean:
		@$(RM) *.#{$OBJEXT} *.so *.sl *.#{$LIBEXT} $(DLLIB)
#{
if /bccwin32/ =~ RUBY_PLATFORM
  "		@$(RM) *.def *.ilc *.ild *.ilf *.ils *.map *.tds *.bak $(CLEANFILES)\n" +
  "		@if exist $(target).def.org ren $(target).def.org $(target).def"
else
  "		@$(RM) *.ilk *.exp *.pdb *.bak $(CLEANFILES)"
end
}

distclean:	clean
		@$(RM) Makefile extconf.h conftest.*
		@$(RM) core ruby$(EXEEXT) *~ $(DISTCLEANFILES)

realclean:	distclean
EOS

  mfile.printf <<EOS

install:
	@$(MAKEDIRS) $(DESTDIR)$(libdir) $(DESTDIR)$(pkglibdir) $(DESTDIR)$(archdir)$(target_prefix)
EOS
  unless $static
    mfile.printf "\
	@$(INSTALL_PROG) $(DLLIB) $(DESTDIR)$(archdir)$(target_prefix)/$(DLLIB)
"
  end
  save_srcdir = Config::CONFIG['srcdir']
  Config::CONFIG['srcdir'] = $srcdir
  install_rb(mfile, '$(DESTDIR)$(rubylibdir)$(target_prefix)', '$(srcdir)')
  Config::CONFIG['srcdir'] = save_srcdir
  mfile.printf "\n"

  unless /mswin32/ =~ RUBY_PLATFORM
    if /bccwin32/ =~ RUBY_PLATFORM
      src = '$(<:\\=/)'
    else
      src = '$<'
    end
    copt = cxxopt = ''
  else
    if /nmake/i =~ $make
      src = '$(<:\\=/)'
    else
      src = '$(subst /,\\\\,$<)'
    end
    copt = '-Tc'
    cxxopt = '-Tp'
  end
  unless /nmake/i =~ $make
    if /bccwin32/ =~ RUBY_PLATFORM
    mfile.print "
{$(srcdir)}.cc{}.#{CONFIG['OBJEXT']}:
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -c #{cxxopt}#{src}
{$(srcdir)}.cpp{}.#{CONFIG['OBJEXT']}:
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -c #{cxxopt}#{src}
{$(srcdir)}.cxx{}.#{CONFIG['OBJEXT']}:
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -c #{cxxopt}#{src}
{$(srcdir)}.c{}.#{CONFIG['OBJEXT']}:
	$(CC) $(CFLAGS) $(CPPFLAGS) -c #{copt}#{src}
"
    end
    mfile.puts "
.cc.#{CONFIG['OBJEXT']}:
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -c #{cxxopt}#{src}
.cpp.#{CONFIG['OBJEXT']}:
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -c #{cxxopt}#{src}
.cxx.#{CONFIG['OBJEXT']}:
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -c #{cxxopt}#{src}
.C.#{CONFIG['OBJEXT']}:
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -c #{cxxopt}#{src}
.c.#{CONFIG['OBJEXT']}:
	$(CC) $(CFLAGS) $(CPPFLAGS) -c #{copt}#{src}
"
  else
    mfile.print "
{$(srcdir)}.c{}.#{CONFIG['OBJEXT']}:
	$(CC) -I. -I$(<D) $(CFLAGS) $(CPPFLAGS) -c #{copt}#{src}
.c.#{CONFIG['OBJEXT']}:
	$(CC) $(CFLAGS) $(CPPFLAGS) -c #{copt}#{src}
{$(srcdir)}.cc{}.#{CONFIG['OBJEXT']}:
	$(CXX) -I. -I$(<D) $(CXXFLAGS) $(CPPFLAGS) -c #{cxxopt}#{src}
.cc.#{CONFIG['OBJEXT']}:
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -c #{cxxopt}#{src}
{$(srcdir)}.cpp{}.#{CONFIG['OBJEXT']}:
	$(CXX) -I. -I$(<D) $(CXXFLAGS) $(CPPFLAGS) -c #{cxxopt}#{src}
.cpp.#{CONFIG['OBJEXT']}:
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -c #{cxxopt}#{src}
{$(srcdir)}.cxx{}.#{CONFIG['OBJEXT']}:
	$(CXX) -I. -I$(<D) $(CXXFLAGS) $(CPPFLAGS) -c #{cxxopt}#{src}
.cxx.#{CONFIG['OBJEXT']}:
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -c #{cxxopt}#{src}
"
  end

  if $static
    if CONFIG['AR'] =~ /^lib\b/i
      mfile.printf "\
$(DLLIB): $(OBJS)
	#{CONFIG['AR']} /OUT:$(DLLIB) $(OBJS)
"
    else
      mfile.printf "\
$(DLLIB): $(OBJS)
	#{CONFIG['AR']} cru $(DLLIB) $(OBJS)
	@-#{CONFIG['RANLIB']} $(DLLIB) 2> /dev/null || true
"
    end
  elsif CONFIG['DLEXT'] != $OBJEXT
    mfile.print "$(DLLIB): $(OBJS)\n"
    if /bccwin32/ =~ RUBY_PLATFORM 
      mfile.print "\t$(LDSHARED) $(DLDFLAGS) C0D32.OBJ $(OBJS), $@,, CW32.LIB IMPORT32.LIB WS2_32.LIB $(LIBS), #{deffile}\n"
    else
      if /mswin32/ =~ RUBY_PLATFORM
        if /nmake/i =~ $make
          mfile.print "\tset LIB=$(LIBPATH:/=\\);$(LIB)\n"
        else
          mfile.print "\tenv LIB='$(subst /,\\\\,$(LIBPATH));$(LIB)' \\\n"
        end
      end
      mfile.print "\t$(LDSHARED) $(DLDFLAGS) #{OUTFLAG}$(DLLIB) $(OBJS) $(LIBS) $(LOCAL_LIBS)\n"
    end
  elsif RUBY_PLATFORM == "m68k-human"
    mfile.printf "\
$(DLLIB): $(OBJS)
	ar cru $(DLLIB) $(OBJS)
"
  else
    mfile.printf "\
$(DLLIB): $(OBJS)
	ld $(DLDFLAGS) -r -o $(DLLIB) $(OBJS)
"
  end

  if File.exist?("#{$srcdir}/depend")
    dfile = open("#{$srcdir}/depend", "r")
    mfile.printf "###\n"
    while line = dfile.gets()
      line.gsub!(/\.o\b/, ".#{$OBJEXT}")
      if /bccwin32/ =~ RUBY_PLATFORM
        line.gsub!(/(\s)([^\s\/]+\.[ch])/, '\1{$(srcdir)}\2')
      else
        line.gsub!(/(\s)([^\s\/]+\.[ch])/, '\1{$(srcdir)}\2') if /nmake/i =~ $make
      end
      mfile.printf "%s", line.gsub(/\$\(hdrdir\)\/config.h/, '$(topdir)/config.h')
    end
    dfile.close
  end
  mfile.close
end

def extmake(target)
  if $force_static or $static_ext[target]
    $static = target
  else
    $static = false
  end

  unless $install or $clean
    return if $nodynamic and not $static
  end

  $OBJEXT = CONFIG['OBJEXT']
  $LIBEXT = "a"
  $objs = nil
  $libs = CONFIG['DLDLIBS'].dup
  $local_flags = ""
  if /mswin32/ =~ RUBY_PLATFORM
    $LIBEXT = "lib"
    $local_flags = "-link /INCREMENTAL:no /EXPORT:Init_$(TARGET)"
  elsif /bccwin32/ =~ RUBY_PLATFORM
    $LIBEXT = "lib"
  end
  $LOCAL_LIBS = ""		# to be assigned in extconf.rb
  $CFLAGS = ""
  $CPPFLAGS = CONFIG['CPPFLAGS']
  $LDFLAGS = ""
  $LIBPATH = [$libdir]
  $INCFLAGS = "-I#{$topdir}"

  dir_config("opt")

  begin
    dir = Dir.pwd
    File.mkpath target unless File.directory?(target)
    Dir.chdir target
    $target = target
    $mdir = target
    unless $install or $clean
      if $static_ext.size > 0 ||
	!File.exist?("./Makefile") ||
	older("./Makefile", $setup) ||
	older("./Makefile", "#{$top_srcdir}/ext/extmk.rb") ||
	older("./Makefile", "#{$top_srcdir}/ext/#{target}/makefile.rb") ||
	older("./Makefile", "#{$top_srcdir}/ext/#{target}/extconf.rb")
      then
	$defs = []
	Logging::logfile 'mkmf.log'
	if File.exist?("#{$top_srcdir}/ext/#{target}/makefile.rb")
	  load "#{$top_srcdir}/ext/#{target}/makefile.rb"
	elsif File.exist?("#{$top_srcdir}/ext/#{target}/extconf.rb")
	  load "#{$top_srcdir}/ext/#{target}/extconf.rb"
	else
	  create_makefile(target)
	end
      end
    end
    if File.exist?("./Makefile")
      if $static
 	$extlist.push [$static, $target, File.basename($target)]
      end
      if $install
        if /bccwin32/ =~ RUBY_PLATFORM
          system "#{$make} -DDESTDIR=#{$destdir} install"
        else
          system "#{$make} install DESTDIR=#{$destdir}"
        end
      elsif $clean
	system "#{$make} #{$clean}"
      else
	unless system "#{$make} all"
	  if ENV["MAKEFLAGS"] != "k" and ENV["MFLAGS"] != "-k"
	    exit
	  end
	end
      end
    end
    if $static
      $extlibs ||= ""
      $extlibs += " " + $DLDFLAGS if $DLDFLAGS
      $extlibs += " " + $LDFLAGS unless $LDFLAGS == ""
      $extlibs += " " + $libs unless $libs == ""
      $extlibs += " " + $LOCAL_LIBS unless $LOCAL_LIBS == ""
    end
  ensure
    rm_f "conftest*"
    Dir.chdir dir
  end
end

$make = ENV["MAKE"]
$make ||= with_config("make-prog", "make")

File::makedirs('ext')
Dir::chdir('ext')

# get static-link modules
$static_ext = {}
for setup in [CONFIG['setup'], File::join($top_srcdir, "ext", CONFIG['setup'])]
  if File.file? setup
    f = open(setup) 
    while line = f.gets()
      line.chomp!
      line.sub!(/#.*$/, '')
      next if /^\s*$/ =~ line
      if /^option +nodynamic/ =~ line
	$nodynamic = true
	next
      end
      target = line.split[0]
      target = target.downcase if /mswin32|bccwin32/ =~ RUBY_PLATFORM
      $static_ext[target] = true
    end
    $setup = setup
    f.close
    break
  end
end

ext_prefix = "#{$top_srcdir}/ext"
for d in Dir["#{ext_prefix}/**/*"]
  File.directory?(d) || next
  File.file?(d + "/MANIFEST") || next
  
  d.slice!(0, ext_prefix.length + 1)
  if $install
    print "installing ", d, "\n"
  elsif $clean
    print "cleaning ", d, "\n"
  else
    print "compiling ", d, "\n"
    if RUBY_PLATFORM =~ /-aix/ and older("../ruby.imp", "../miniruby")
      load "#{$top_srcdir}/ext/aix_mksym.rb"
    end
  end
  $stdout.flush
  extmake(d)
end

if $install or $clean
  Dir.chdir ".."
  exit
end
$extinit = "" unless $extinit

ruby = CONFIG["RUBY_INSTALL_NAME"] + CONFIG["EXEEXT"]
miniruby = "miniruby" + CONFIG["EXEEXT"]

$extobjs = "" unless $extobjs
if $extlist.size > 0
  for s,t,i in $extlist
    f = format("%s/%s.%s", s, i, $LIBEXT)
    if File.exist?(f)
      $extinit += format("\
\tInit_%s();\n\
\trb_provide(\"%s.so\");\n\
", i, t)
      $extobjs += "ext/"
      $extobjs += f
      $extobjs += " "
    else
      false
    end
  end

  if older("extinit.c", $setup) || older("extinit.c", "#{$top_srcdir}/ext/extmk.rb")
    f = open("extinit.c", "w")
    f.printf "void Init_ext() {\n"
    f.printf $extinit
    f.printf "}\n"
    f.close
  end
  if older("extinit.#{$OBJEXT}", "extinit.c")
    cmd = CONFIG["CC"] + " " + CFLAGS + " -c extinit.c"
    print cmd, "\n"
    system cmd or exit 1
  end

  Dir.chdir ".."

  if older(ruby, $setup) or older(ruby, miniruby)
    rm_f ruby
  end

  $extobjs = "ext/extinit.#{$OBJEXT} " + $extobjs
  if RUBY_PLATFORM =~ /m68k-human|beos/
    $extlibs.gsub!("-L/usr/local/lib", "") if $extlibs
  end
  system format(%[#{$make} #{ruby} EXTOBJS='%s' EXTLIBS='%s'], $extobjs, $extlibs)
else
  Dir.chdir ".."
  if older(ruby, miniruby)
    rm_f ruby
    system("#{$make} #{ruby}")
  end
end

#Local variables:
# mode: ruby
#end:
