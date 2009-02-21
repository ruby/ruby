#! /usr/local/bin/ruby
# -*- ruby -*-

$extension = nil
$extstatic = nil
$force_static = nil
$install = nil
$destdir = nil
$dryrun = false
$clean = nil
$nodynamic = nil
$extinit = nil
$extobjs = nil
$extflags = ""
$extlibs = nil
$extpath = nil
$ignore = nil
$message = nil

$progname = $0
alias $PROGRAM_NAME $0
alias $0 $progname

$extlist = []
$compiled = {}

$:.replace([Dir.pwd])
require 'rbconfig'

srcdir = File.dirname(File.dirname(__FILE__))

$:.unshift(srcdir, File.expand_path("lib", srcdir))

$topdir = "."
$top_srcdir = srcdir

require 'mkmf'
require 'optparse/shellwords'

def sysquote(x)
  @quote ||= /human|os2|macos/ =~ (CROSS_COMPILING || RUBY_PLATFORM)
  @quote ? x.quote : x
end

def relative_from(path, base)
  dir = File.join(path, "")
  if File.expand_path(dir) == File.expand_path(dir, base)
    path
  else
    File.join(base, path)
  end
end

def extract_makefile(makefile, keep = true)
  m = File.read(makefile)
  if !(target = m[/^TARGET[ \t]*=[ \t]*(\S*)/, 1])
    return keep
  end
  installrb = {}
  m.scan(/^install-rb-default:[ \t]*(\S+)\n\1:[ \t]*(\S+)/) {installrb[$2] = $1}
  oldrb = installrb.keys.sort
  newrb = install_rb(nil, "").collect {|d, *f| f}.flatten.sort
  if target_prefix = m[/^target_prefix[ \t]*=[ \t]*\/(.*)/, 1]
    target = "#{target_prefix}/#{target}"
  end
  unless oldrb == newrb
    if $extout
      newrb.each {|f| installrb.delete(f)}
      unless installrb.empty?
        config = CONFIG.dup
        install_dirs(target_prefix).each {|var, val| config[var] = val}
        FileUtils.rm_f(installrb.values.collect {|f| Config.expand(f, config)}, :verbose => true)
      end
    end
    return false
  end
  $target = target
  $extconf_h = m[/^RUBY_EXTCONF_H[ \t]*=[ \t]*(\S+)/, 1]
  $static ||= m[/^EXTSTATIC[ \t]*=[ \t]*(\S+)/, 1] || false
  /^STATIC_LIB[ \t]*=[ \t]*\S+/ =~ m or $static = nil
  $preload = Shellwords.shellwords(m[/^preload[ \t]*=[ \t]*(.*)/, 1] || "")
  $DLDFLAGS += " " + (m[/^dldflags[ \t]*=[ \t]*(.*)/, 1] || "")
  if s = m[/^LIBS[ \t]*=[ \t]*(.*)/, 1]
    s.sub!(/^#{Regexp.quote($LIBRUBYARG)} */, "")
    s.sub!(/ *#{Regexp.quote($LIBS)}$/, "")
    $libs = s
  end
  $objs = (m[/^OBJS[ \t]*=[ \t](.*)/, 1] || "").split
  $srcs = (m[/^SRCS[ \t]*=[ \t](.*)/, 1] || "").split
  $LOCAL_LIBS = m[/^LOCAL_LIBS[ \t]*=[ \t]*(.*)/, 1] || ""
  $LIBPATH = Shellwords.shellwords(m[/^libpath[ \t]*=[ \t]*(.*)/, 1] || "") - %w[$(libdir) $(topdir)]
  true
end

def extmake(target)
  print "#{$message} #{target}\n"
  $stdout.flush
  if $force_static or $static_ext[target]
    $static = target
  else
    $static = false
  end

  unless $ignore
    return true if $nodynamic and not $static
  end

  FileUtils.mkpath target unless File.directory?(target)
  begin
    dir = Dir.pwd
    FileUtils.mkpath target unless File.directory?(target)
    Dir.chdir target
    top_srcdir = $top_srcdir
    topdir = $topdir
    hdrdir = $hdrdir
    prefix = "../" * (target.count("/")+1)
    $top_srcdir = relative_from(top_srcdir, prefix)
    $hdrdir = relative_from(hdrdir, prefix)
    $topdir = prefix + $topdir
    $target = target
    $mdir = target
    $srcdir = File.join($top_srcdir, "ext", $mdir)
    $preload = nil
    $objs = ""
    $srcs = ""
    $compiled[target] = false
    makefile = "./Makefile"
    ok = File.exist?(makefile)
    unless $ignore
      rbconfig0 = Config::CONFIG
      mkconfig0 = CONFIG
      rbconfig = {
	"hdrdir" => $hdrdir,
	"srcdir" => $srcdir,
	"topdir" => $topdir,
      }
      mkconfig = {
	"hdrdir" => "$(top_srcdir)",
	"srcdir" => "$(top_srcdir)/ext/#{$mdir}",
	"topdir" => $topdir,
      }
      rbconfig0.each_pair {|key, val| rbconfig[key] ||= val.dup}
      mkconfig0.each_pair {|key, val| mkconfig[key] ||= val.dup}
      Config.module_eval {
	remove_const(:CONFIG)
	const_set(:CONFIG, rbconfig)
	remove_const(:MAKEFILE_CONFIG)
	const_set(:MAKEFILE_CONFIG, mkconfig)
      }
      Object.class_eval {
	remove_const(:CONFIG)
	const_set(:CONFIG, mkconfig)
      }
      begin
	$extconf_h = nil
	ok &&= extract_makefile(makefile)
	conf = ["#{$srcdir}/makefile.rb", "#{$srcdir}/extconf.rb"].find {|f| File.exist?(f)}
	if (($extconf_h && !File.exist?($extconf_h)) ||
	    !(t = modified?(makefile, MTIMES)) ||
	    [conf, "#{$srcdir}/depend"].any? {|f| modified?(f, [t])})
        then
	  ok = false
          init_mkmf
	  Logging::logfile 'mkmf.log'
	  rm_f makefile
	  if conf
	    load $0 = conf
	  else
	    create_makefile(target)
	  end
	  $defs << "-DRUBY_EXPORT" if $static
	  ok = File.exist?(makefile)
	end
      rescue SystemExit
	# ignore
      ensure
	rm_f "conftest*"
	config = $0
	$0 = $PROGRAM_NAME
      end
    end
    ok = yield(ok) if block_given?
    unless ok
      open(makefile, "w") do |f|
	f.print dummy_makefile(CONFIG["srcdir"])
      end
      return true
    end
    args = sysquote($mflags)
    unless $destdir.to_s.empty? or $mflags.include?("DESTDIR")
      args += [sysquote("DESTDIR=" + relative_from($destdir, "../"+prefix))]
    end
    if $static
      args += ["static"] unless $clean
      $extlist.push [$static, $target, File.basename($target), $preload]
    end
    unless system($make, *args)
      $ignore or $continue or return false
    end
    $compiled[target] = true
    if $clean
      FileUtils.rm_f("mkmf.log")
      if $clean != true
	FileUtils.rm_f([makefile, $extconf_h || "extconf.h"])
      end
      File.unlink(makefile) rescue nil
    end
    if $static
      $extflags ||= ""
      $extlibs ||= []
      $extpath ||= []
      unless $mswin
        $extflags = ($extflags.split | $DLDFLAGS.split | $LDFLAGS.split).join(" ")
      end
      $extlibs = merge_libs($extlibs, $libs.split, $LOCAL_LIBS.split)
      $extpath |= $LIBPATH
    end
  ensure
    unless $ignore
      Config.module_eval {
	remove_const(:CONFIG)
	const_set(:CONFIG, rbconfig0)
	remove_const(:MAKEFILE_CONFIG)
	const_set(:MAKEFILE_CONFIG, mkconfig0)
      }
      Object.class_eval {
	remove_const(:CONFIG)
	const_set(:CONFIG, mkconfig0)
      }
    end
    $top_srcdir = top_srcdir
    $topdir = topdir
    $hdrdir = hdrdir
    Dir.chdir dir
  end
  begin
    Dir.rmdir target
    target = File.dirname(target)
  rescue SystemCallError
    break
  end while true
  true
end

def compiled?(target)
  $compiled[target]
end

def parse_args()
  $mflags = []

  opts = nil
  $optparser ||= OptionParser.new do |opts|
    opts.on('-n') {$dryrun = true}
    opts.on('--[no-]extension [EXTS]', Array) do |v|
      $extension = (v == false ? [] : v)
    end
    opts.on('--[no-]extstatic [STATIC]', Array) do |v|
      if ($extstatic = v) == false
        $extstatic = []
      elsif v
        $force_static = true if $extstatic.delete("static")
        $extstatic = nil if $extstatic.empty?
      end
    end
    opts.on('--dest-dir=DIR') do |v|
      $destdir = v
    end
    opts.on('--extout=DIR') do |v|
      $extout = (v unless v.empty?)
    end
    opts.on('--make=MAKE') do |v|
      $make = v || 'make'
    end
    opts.on('--make-flags=FLAGS', '--mflags', Shellwords) do |v|
      v.grep(/\A([-\w]+)=(.*)/) {$configure_args["--#{$1}"] = $2}
      if arg = v.first
        arg.insert(0, '-') if /\A[^-][^=]*\Z/ =~ arg
      end
      $mflags.concat(v)
    end
    opts.on('--message [MESSAGE]', String) do |v|
      $message = v
    end
  end
  begin
    $optparser.parse!(ARGV)
  rescue OptionParser::InvalidOption => e
    retry if /^--/ =~ e.args[0]
    $optparser.warn(e)
    abort opts.to_s
  end

  $destdir ||= ''

  $make, *rest = Shellwords.shellwords($make)
  $mflags.unshift(*rest) unless rest.empty?

  def $mflags.set?(flag)
    grep(/\A-(?!-).*#{flag.chr}/i) { return true }
    false
  end
  def $mflags.defined?(var)
    grep(/\A#{var}=(.*)/) {return $1}
    false
  end

  if $mflags.set?(?n)
    $dryrun = true
  else
    $mflags.unshift '-n' if $dryrun
  end

  $continue = $mflags.set?(?k)
  if $extout
    $extout = '$(topdir)/'+$extout
    Config::CONFIG["extout"] = CONFIG["extout"] = $extout
    $extout_prefix = $extout ? "$(extout)$(target_prefix)/" : ""
    $mflags << "extout=#$extout" << "extout_prefix=#$extout_prefix"
  end
end

parse_args()

if target = ARGV.shift and /^[a-z-]+$/ =~ target
  $mflags.push(target)
  case target
  when /^(dist|real)?(clean)$/
    target = $2
    $ignore ||= true
    $clean = $1 ? $1[0] : true
  when /^install\b/
    $install = true
    $ignore ||= true
    $mflags.unshift("INSTALL_PROG=install -c -p -m 0755",
                    "INSTALL_DATA=install -c -p -m 0644",
                    "MAKEDIRS=mkdir -p") if $dryrun
  end
end
unless $message
  if target
    $message = target.sub(/^(\w+)e?\b/, '\1ing').tr('-', ' ')
  else
    $message = "compiling"
  end
end

EXEEXT = CONFIG['EXEEXT']
if CROSS_COMPILING
  $ruby = CONFIG['MINIRUBY']
elsif sep = config_string('BUILD_FILE_SEPARATOR')
  $ruby = "$(topdir:/=#{sep})#{sep}miniruby" + EXEEXT
else
  $ruby = '$(topdir)/miniruby' + EXEEXT
end
$ruby << " -I'$(topdir)'"
unless CROSS_COMPILING
  $ruby << " -I'$(top_srcdir)/lib'"
  $ruby << " -I'$(extout)/$(arch)' -I'$(extout)/common'" if $extout
  $ruby << " -I./- -I'$(top_srcdir)/ext' -rpurelib.rb"
  ENV["RUBYLIB"] = "-"
  ENV["RUBYOPT"] = "-rpurelib.rb"
end
$config_h = '$(topdir)/config.h'
$mflags << "ruby=#$ruby"

MTIMES = [__FILE__, 'rbconfig.rb', srcdir+'/lib/mkmf.rb'].collect {|f| File.mtime(f)}

# get static-link modules
$static_ext = {}
if $extstatic
  $extstatic.each do |target|
    target = target.downcase if /mswin32|bccwin32/ =~ RUBY_PLATFORM
    $static_ext[target] = $static_ext.size
  end
end
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
      $static_ext[target] = $static_ext.size
    end
    MTIMES << f.mtime
    $setup = setup
    f.close
    break
  end
end unless $extstatic

ext_prefix = "#{$top_srcdir}/ext"
exts = $static_ext.sort_by {|t, i| i}.collect {|t, i| t}
if $extension
  exts |= $extension.select {|d| File.directory?("#{ext_prefix}/#{d}")}
else
  withes, withouts = %w[--with --without].collect {|w|
    if not (w = %w[-extensions -ext].collect {|opt|arg_config(w+opt)}).any?
      proc {false}
    elsif (w = w.grep(String)).empty?
      proc {true}
    else
      proc {|c1| w.collect {|opt| opt.split(/,/)}.flatten.any?(&c1)}
    end
  }
  cond = proc {|ext|
    cond1 = proc {|n| File.fnmatch(n, ext, File::FNM_PATHNAME)}
    withes.call(cond1) or !withouts.call(cond1)
  }
  exts |= Dir.glob("#{ext_prefix}/*/**/extconf.rb").collect {|d|
    d = File.dirname(d)
    d.slice!(0, ext_prefix.length + 1)
    d
  }.find_all {|ext|
    with_config(ext, &cond)
  }.sort
end

if $extout
  extout = Config.expand("#{$extout}", Config::CONFIG.merge("topdir"=>$topdir))
  unless $ignore
    FileUtils.mkpath(extout)
  end
end

dir = Dir.pwd
FileUtils::makedirs('ext')
Dir::chdir('ext')

hdrdir = $hdrdir
$hdrdir = $top_srcdir = relative_from(srcdir, $topdir = "..")
exts.each do |d|
  extmake(d) or abort
end
$top_srcdir = srcdir
$topdir = "."
$hdrdir = hdrdir

extinit = Struct.new(:c, :o) {
  def initialize(src)
    super("#{src}.c", "#{src}.#{$OBJEXT}")
  end
}.new("extinit")
if $ignore
  FileUtils.rm_f(extinit.to_a) if $clean
  Dir.chdir ".."
  if $clean
    Dir.rmdir('ext') rescue nil
    if $extout
      FileUtils.rm_rf([extout+"/common", extout+"/include/ruby", extout+"/rdoc"])
      FileUtils.rm_rf(extout+"/"+CONFIG["arch"])
      if $clean != true
	FileUtils.rm_rf(extout+"/include/"+CONFIG["arch"])
	FileUtils.rm_f($mflags.defined?("INSTALLED_LIST")||ENV["INSTALLED_LIST"]||".installed.list")
	Dir.rmdir(extout+"/include") rescue nil
	Dir.rmdir(extout) rescue nil
      end
    end
  end
  exit
end

$extinit ||= ""
$extobjs ||= ""
$extpath ||= []
$extflags ||= ""
$extlibs ||= []
unless $extlist.empty?
  $extinit << "\n" unless $extinit.empty?
  list = $extlist.dup
  built = []
  while e = list.shift
    s,t,i,r = e
    if r and !(r -= built).empty?
      l = list.size
      if (while l > 0; break true if r.include?(list[l-=1][1]) end)
        list.insert(l + 1, e)
      end
      next
    end
    f = format("%s/%s.%s", s, i, $LIBEXT)
    if File.exist?(f)
      $extinit << "    init(Init_#{i}, \"#{t}.so\");\n"
      $extobjs << "ext/#{f} "
      built << t
    end
  end

  src = %{\
#include "ruby.h"

#define init(func, name) {void func _((void)); ruby_init_ext(name, func);}

void ruby_init_ext _((const char *name, void (*init)(void)));

void Init_ext _((void))\n{\n#$extinit}
}
  if !modified?(extinit.c, MTIMES) || IO.read(extinit.c) != src
    open(extinit.c, "w") {|f| f.print src}
  end

  $extobjs = "ext/#{extinit.o} #{$extobjs}"
  if RUBY_PLATFORM =~ /m68k-human|beos/
    $extflags.delete("-L/usr/local/lib")
  end
  $extpath.delete("$(topdir)")
  $extflags = libpathflag($extpath) << " " << $extflags.strip
  conf = [
    ['LIBRUBY_SO_UPDATE', '$(LIBRUBY_EXTS)'],
    ['SETUP', $setup],
    [enable_config("shared", $enable_shared) ? 'DLDOBJS' : 'EXTOBJS', $extobjs],
    ['EXTLIBS', $extlibs.join(' ')], ['EXTLDFLAGS', $extflags]
  ].map {|n, v|
    "#{n}=#{v}" if v and !(v = v.strip).empty?
  }.compact
  puts conf
  $stdout.flush
  $mflags.concat(conf)
else
  FileUtils.rm_f(extinit.to_a)
end
rubies = []
%w[RUBY RUBYW STATIC_RUBY].each {|r|
  n = r
  if r = arg_config("--"+r.downcase) || config_string(r+"_INSTALL_NAME")
    rubies << Config.expand(r+=EXEEXT)
    $mflags << "#{n}=#{r}"
  end
}

Dir.chdir ".."
unless $destdir.to_s.empty?
  $mflags.defined?("DESTDIR") or $mflags << "DESTDIR=#{$destdir}"
end
puts "making #{rubies.join(', ')}"
$stdout.flush
$mflags.concat(rubies)

if $nmake == ?b
  unless (vars = $mflags.grep(/\A\w+=/n)).empty?
    open(mkf = "libruby.mk", "wb") do |tmf|
      tmf.puts("!include Makefile")
      tmf.puts
      tmf.puts(*vars.map {|v| v.sub(/=/, " = ")})
      tmf.puts("PRE_LIBRUBY_UPDATE = del #{mkf}")
    end
    $mflags.unshift("-f#{mkf}")
    vars.each {|flag| flag.sub!(/\A/, "-D")}
  end
end
system($make, *sysquote($mflags)) or exit($?.exitstatus)

#Local variables:
# mode: ruby
#end:
