#! /usr/local/bin/ruby -s
# -*- ruby -*-

$force_static = nil
$install = nil
$destdir = nil
$clean = nil
$nodynamic = nil
$extinit = nil
$extobjs = nil

$extlist = []

$:.replace ["."]
require 'rbconfig'

srcdir = Config::CONFIG["srcdir"]

$:.replace [srcdir, srcdir+"/lib", "."]

require 'mkmf'
require 'ftools'
require 'shellwords'

$topdir = File.expand_path(".")
$top_srcdir = srcdir
$hdrdir = $top_srcdir

def extmake(target)
  print "#{$message} #{target}\n"
  $stdout.flush
  if $force_static or $static_ext[target]
    $static = target
  else
    $static = false
  end

  unless $ignore
    return if $nodynamic and not $static
  end

  init_mkmf

  begin
    dir = Dir.pwd
    File.mkpath target unless File.directory?(target)
    Dir.chdir target
    $target = target
    $mdir = target
    $srcdir = File.join($top_srcdir, "ext", $mdir)
    unless $ignore
      if $static ||
	older("./Makefile", *MTIMES + %W"#{$srcdir}/makefile.rb #{$srcdir}/extconf.rb")
      then
	$defs = []
	Logging::logfile 'mkmf.log'
	Config::CONFIG["srcdir"] = $srcdir
	if File.exist?("#{$srcdir}/makefile.rb")
	  load "#{$srcdir}/makefile.rb"
	elsif File.exist?("#{$srcdir}/extconf.rb")
	  load "#{$srcdir}/extconf.rb"
	else
	  create_makefile(target)
	end
	Config::CONFIG["srcdir"] = $top_srcdir
      end
    end
    if File.exist?("./Makefile")
      if $static
	$extlist.push [$static, $target, File.basename($target)]
      end
      unless system *ARGV
	$ignore or $continue or exit(1)
      end
    else
      open("./Makefile", "w") {|f|
        f.print configuration($srcdir), makerules(nil), "install:\n"
        if /bccwin32/ =~ RUBY_PLATFORM
          f.print "\t@\n"
        end
      }
    end
    if $static
      $extflags ||= ""
      $extlibs ||= ""
      $extflags += " " + $DLDFLAGS if $DLDFLAGS
      $extflags += " " + $LDFLAGS unless $LDFLAGS == ""
      $extlibs += " " + $libs unless $libs == ""
      $extlibs += " " + $LOCAL_LIBS unless $LOCAL_LIBS == ""
    end
  rescue SystemExit
    # ignore
  ensure
    rm_f "conftest*"
    Dir.chdir dir
  end
end

if ARGV[0] == "static"
  ARGV.shift
  $force_static = true
end

$make = ARGV[0] if ARGV[0]
ARGV << $make if ARGV.empty? and $make
if mflags = ENV["MAKEFLAGS"]
  mflags, = mflags.split(nil, 2)
else
  mflags = ENV["MFLAGS"] || ""
end
$continue = mflags.include?(?k)
$dryrun = mflags.include?(?n)

unless $message
  if ARGV.size > 1 and /^[a-z]+$/ =~ ($message = ARGV[-1])
    $message = $message.sub(/^(?:dist|real)(?=(?:clean)?$)/, '\1')
    case $message
    when "clean"
      $ignore ||= true
    when "install"
      $ignore ||= true
      ARGV[1, 0] = ["INSTALL_PROG=install -m 0755", "INSTALL_DATA=install -m 0644"] if $dryrun
    end
    $message.sub!(/e?$/, "ing")
  else
    $message = "compiling"
  end
end

EXEEXT = CONFIG['EXEEXT']
if defined? CROSS_COMPILING
  $ruby = CONFIG['MINIRUBY']
elsif $nmake
  $ruby = '$(topdir:/=\\)\\miniruby' + EXEEXT
else
  $ruby = '$(topdir)/miniruby' + EXEEXT
end
$ruby << " -I$(topdir) -I$(hdrdir)/lib"
$config_h = '$(topdir)/config.h'

MTIMES = [File.mtime(__FILE__)]

# get static-link modules
$static_ext = {}
for dir in ["ext", File::join($top_srcdir, "ext")]
  setup = File::join(dir, CONFIG['setup'])
  if File.file? setup
    f = open(setup) 
    while line = f.gets()
      line.chomp!
      line.sub!(/#.*$/, '')
      next if /^\s*$/ =~ line
      target, opt = line.split(nil, 3)
      if target == 'option'
	case opt
	when 'nodynamic'
	  $nodynamic = true
	end
	next
      end
      target = target.downcase if /mswin32|bccwin32/ =~ RUBY_PLATFORM
      $static_ext[target] = true
    end
    MTIMES << f.mtime
    $setup = setup
    f.close
    break
  end
end

File::makedirs('ext')
Dir::chdir('ext')

ext_prefix = "#{$top_srcdir}/ext"
Dir.glob("#{ext_prefix}/**/MANIFEST") do |d|
  d = File.dirname(d)
  d.slice!(0, ext_prefix.length + 1)
  extmake(d)
end

if $ignore
  Dir.chdir ".."
  exit
end

if $extlist.size > 0
  $extinit ||= ""
  $extobjs ||= ""
  for s,t,i in $extlist
    f = format("%s/%s.%s", s, i, $LIBEXT)
    if File.exist?(f)
      $extinit += "\tInit_#{i}();\n\trb_provide(\"#{t}.so\");\n"
      $extobjs += "ext/#{f} "
    end
  end

  src = "void Init_ext() {\n#$extinit}\n"
  if older("extinit.c", *MTIMES) || IO.read("extinit.c") != src
    open("extinit.c", "w") {|f| f.print src}
  end

  $extobjs = "ext/extinit.#{$OBJEXT} " + $extobjs
  if RUBY_PLATFORM =~ /m68k-human|beos/
    $extlibs.gsub!("-L/usr/local/lib", "") if $extlibs
  end
  conf = [
    ['SETUP', $setup], ['EXTOBJS', $extobjs],
    ['EXTLIBS', $extlibs], ['EXTLDFLAGS', $extflags]
  ].map {|n, v|
    "#{n}=#{v}" if v and !(v = v.strip).empty?
  }.compact
  puts conf
  $stdout.flush
  ARGV.concat(conf)
end
rubies = []
%w[RUBY RUBYW].each {|r|
  r = CONFIG[r+"_INSTALL_NAME"] and !r.empty? and rubies << r+EXEEXT
}

Dir.chdir ".."
puts "making #{rubies.join(', ')}"
$stdout.flush
ARGV.concat(rubies)
host = (defined?(CROSS_COMPILING) ? CROSS_COMPILING : RUBY_PLATFORM)
/mswin|bccwin|mingw|djgpp|human|os2|macos/ =~ host or exec(*ARGV)
system(*ARGV.quote) or exit($?.exitstatus)

#Local variables:
# mode: ruby
#end:
