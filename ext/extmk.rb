#! /usr/local/bin/ruby
# -*- mode: ruby; coding: us-ascii -*-
# frozen_string_literal: false

# :stopdoc:
$extension = nil
$extstatic = nil
$force_static = nil
$install = nil
$destdir = nil
$dryrun = false
$clean = nil
$nodynamic = nil
$extinit = nil
$extobjs = []
$extflags = ""
$extlibs = nil
$extpath = nil
$ignore = nil
$message = nil
$command_output = nil
$configure_only = false

$progname = $0
alias $PROGRAM_NAME $0
alias $0 $progname

$extlist = []

DUMMY_SIGNATURE = "***DUMMY MAKEFILE***"

srcdir = File.dirname(File.dirname(__FILE__))
unless defined?(CROSS_COMPILING) and CROSS_COMPILING
  $:.replace([File.expand_path("lib", srcdir), Dir.pwd])
end
$:.unshift(srcdir)
require 'rbconfig'

$topdir = "."
$top_srcdir = srcdir

$" << "mkmf.rb"
load File.expand_path("lib/mkmf.rb", srcdir)
require 'optparse/shellwords'

if defined?(File::NULL)
  @null = File::NULL
elsif !File.chardev?(@null = "/dev/null")
  @null = "nul"
end

def verbose?
  $mflags.defined?("V") == "1"
end

def system(*args)
  if verbose?
    if args.size == 1
      puts args
    else
      puts Shellwords.join(args)
    end
  end
  super
end

def atomic_write_open(filename)
  filename_new = filename + ".new.#$$"
  open(filename_new, "wb") do |f|
    yield f
  end
  if File.binread(filename_new) != (File.binread(filename) rescue nil)
    File.rename(filename_new, filename)
  else
    File.unlink(filename_new)
  end
end

def extract_makefile(makefile, keep = true)
  m = File.read(makefile)
  s = m[/^CLEANFILES[ \t]*=[ \t](.*)/, 1] and $cleanfiles = s.split
  s = m[/^DISTCLEANFILES[ \t]*=[ \t](.*)/, 1] and $distcleanfiles = s.split
  s = m[/^EXTSO[ \t]*=[ \t](.*)/, 1] and $extso = s.split
  if !(target = m[/^TARGET[ \t]*=[ \t]*(\S*)/, 1])
    return keep
  end
  installrb = {}
  m.scan(/^(?:do-)?install-rb-default:.*[ \t](\S+)(?:[ \t].*)?\n\1:[ \t]*(\S+)/) {installrb[$2] = $1}
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
        FileUtils.rm_f(installrb.values.collect {|f| RbConfig.expand(f, config)},
                       :verbose => verbose?)
      end
    end
    return false
  end
  srcs = Dir[File.join($srcdir, "*.{#{SRC_EXT.join(%q{,})}}")].map {|fn| File.basename(fn)}.sort
  if !srcs.empty?
    old_srcs = m[/^ORIG_SRCS[ \t]*=[ \t](.*)/, 1] or return false
    old_srcs.split.sort == srcs or return false
  end
  $target = target
  $extconf_h = m[/^RUBY_EXTCONF_H[ \t]*=[ \t]*(\S+)/, 1]
  if $static.nil?
    $static ||= m[/^EXTSTATIC[ \t]*=[ \t]*(\S+)/, 1] || false
    /^STATIC_LIB[ \t]*=[ \t]*\S+/ =~ m or $static = false
  end
  $preload = Shellwords.shellwords(m[/^preload[ \t]*=[ \t]*(.*)/, 1] || "")
  if dldflags = m[/^dldflags[ \t]*=[ \t]*(.*)/, 1] and !$DLDFLAGS.include?(dldflags)
    $DLDFLAGS += " " + dldflags
  end
  if s = m[/^LIBS[ \t]*=[ \t]*(.*)/, 1]
    s.sub!(/^#{Regexp.quote($LIBRUBYARG)} */, "")
    s.sub!(/ *#{Regexp.quote($LIBS)}$/, "")
    $libs = s
  end
  $objs = (m[/^OBJS[ \t]*=[ \t](.*)/, 1] || "").split
  $srcs = (m[/^SRCS[ \t]*=[ \t](.*)/, 1] || "").split
  $headers = (m[/^LOCAL_HDRS[ \t]*=[ \t](.*)/, 1] || "").split
  $LOCAL_LIBS = m[/^LOCAL_LIBS[ \t]*=[ \t]*(.*)/, 1] || ""
  $LIBPATH = Shellwords.shellwords(m[/^libpath[ \t]*=[ \t]*(.*)/, 1] || "") - %w[$(libdir) $(topdir)]
  true
end

def extmake(target, basedir = (maybestatic = 'ext'))
  unless $configure_only || verbose?
    print "#{$message} #{target}\n"
    $stdout.flush
  end

  FileUtils.mkpath target unless File.directory?(target)
  begin
    # don't build if parent library isn't build
    parent = true
    d = target
    until (d = File.dirname(d)) == '.'
      if File.exist?("#{$top_srcdir}/#{basedir}/#{d}/extconf.rb")
        parent = (/^all:\s*install/ =~ IO.read("#{d}/Makefile") rescue false)
        break
      end
    end

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
    $srcdir = File.join($top_srcdir, basedir, $mdir)
    $preload = nil
    $objs = []
    $srcs = []
    $extso = []
    makefile = "./Makefile"
    static = $static
    $static = nil if noinstall = File.fnmatch?("-*", target)
    ok = parent && File.exist?(makefile)
    if parent && !$ignore
      rbconfig0 = RbConfig::CONFIG
      mkconfig0 = CONFIG
      rbconfig = {
	"hdrdir" => $hdrdir,
	"srcdir" => $srcdir,
	"topdir" => $topdir,
      }
      mkconfig = {
	"hdrdir" => ($hdrdir == top_srcdir) ? top_srcdir : "$(top_srcdir)/include",
	"srcdir" => "$(top_srcdir)/#{basedir}/#{$mdir}",
	"topdir" => $topdir,
      }
      rbconfig0.each_pair {|key, val| rbconfig[key] ||= val.dup}
      mkconfig0.each_pair {|key, val| mkconfig[key] ||= val.dup}
      RbConfig.module_eval {
	remove_const(:CONFIG)
	const_set(:CONFIG, rbconfig)
	remove_const(:MAKEFILE_CONFIG)
	const_set(:MAKEFILE_CONFIG, mkconfig)
      }
      MakeMakefile.class_eval {
	remove_const(:CONFIG)
	const_set(:CONFIG, mkconfig)
      }
      begin
	$extconf_h = nil
	ok &&= extract_makefile(makefile)
	old_objs = $objs
	old_cleanfiles = $distcleanfiles | $cleanfiles
	conf = ["#{$srcdir}/makefile.rb", "#{$srcdir}/extconf.rb"].find {|f| File.exist?(f)}
	if (!ok || ($extconf_h && !File.exist?($extconf_h)) ||
	    !(t = modified?(makefile, MTIMES)) ||
	    [conf, "#{$srcdir}/depend"].any? {|f| modified?(f, [t])})
        then
	  ok = false
          if $configure_only
            if verbose?
              print "#{conf}\n" if conf
            else
              print "#{$message} #{target}\n"
            end
            $stdout.flush
          end
          init_mkmf
	  Logging::logfile 'mkmf.log'
	  rm_f makefile
	  if conf
            Logging.open do
              unless verbose?
                $stderr.reopen($stdout.reopen(@null))
              end
              load $0 = conf
            end
	  else
	    create_makefile(target)
	  end
	  $defs << "-DRUBY_EXPORT" if $static
	  ok = File.exist?(makefile)
	end
      rescue SystemExit
	# ignore
      rescue => error
        lineno = error.backtrace_locations[0].lineno
        ok = false
      ensure
	rm_f "conftest*"
	$0 = $PROGRAM_NAME
      end
    end
    ok &&= File.open(makefile){|f| s = f.gets and !s[DUMMY_SIGNATURE]}
    unless ok
      mf = ["# #{DUMMY_SIGNATURE}\n", *dummy_makefile(CONFIG["srcdir"])].join("")
      atomic_write_open(makefile) do |f|
        f.print(mf)
      end

      return true if !error and target.start_with?("-")

      if parent
        message = "Failed to configure #{target}. It will not be installed."
      else
        message = "Skipped to configure #{target}. Its parent is not configured."
      end
      if Logging.log_opened?
        Logging::message(error.to_s) if error
        Logging::message(message)
      end
      message = error.message if error

      return parent ? [conf, lineno||0, message] : true
    end
    args = $mflags
    unless $destdir.to_s.empty? or $mflags.defined?("DESTDIR")
      args += ["DESTDIR=" + relative_from($destdir, "../"+prefix)]
    end
    if $static and ok and !$objs.empty? and !noinstall
      args += ["static"] unless $clean
      $extlist.push [(maybestatic ? $static : false), target, $target, $preload]
    end
    FileUtils.rm_f(old_cleanfiles - $distcleanfiles - $cleanfiles)
    FileUtils.rm_f(old_objs - $objs)
    unless $configure_only or system($make, *args)
      $ignore or $continue or return false
    end
    if $clean
      FileUtils.rm_f("mkmf.log")
      if $clean != true
	FileUtils.rm_f([makefile, $extconf_h || "extconf.h"])
      end
    end
    if $static
      $extflags ||= ""
      $extlibs ||= []
      $extpath ||= []
      unless $mswin
        $extflags = split_libs($extflags, $DLDFLAGS, $LDFLAGS).uniq.join(" ")
      end
      $extlibs = merge_libs($extlibs, split_libs($libs, $LOCAL_LIBS).map {|lib| lib.sub(/\A\.\//, "ext/#{target}/")})
      $extpath |= $LIBPATH
    end
  ensure
    Logging::log_close
    if rbconfig0
      RbConfig.module_eval {
	remove_const(:CONFIG)
	const_set(:CONFIG, rbconfig0)
	remove_const(:MAKEFILE_CONFIG)
	const_set(:MAKEFILE_CONFIG, mkconfig0)
      }
    end
    if mkconfig0
      MakeMakefile.class_eval {
	remove_const(:CONFIG)
	const_set(:CONFIG, mkconfig0)
      }
    end
    $top_srcdir = top_srcdir
    $topdir = topdir
    $hdrdir = hdrdir
    $static = static
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

def parse_args()
  $mflags = []
  $makeflags = [] # for make command to build ruby, so quoted

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
      $makeflags.concat(v.reject {|arg2| /\AMINIRUBY=/ =~ arg2}.quote)
      $mflags.concat(v)
    end
    opts.on('--message [MESSAGE]', String) do |v|
      $message = v
    end
    opts.on('--command-output=FILE', String) do |v|
      $command_output = v
    end
    opts.on('--gnumake=yes|no', true) do |v|
      $gnumake = v
    end
    opts.on('--extflags=FLAGS') do |v|
      $extflags = v || ""
    end
  end
  begin
    $optparser.parse!(ARGV)
  rescue OptionParser::InvalidOption => e
    retry if /^--/ =~ e.args[0]
    $optparser.warn(e)
    abort $optparser.to_s
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
    RbConfig::CONFIG["extout"] = CONFIG["extout"] = $extout
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
  when /configure/
    $configure_only = true
  end
end
unless $message
  if target
    $message = target.sub(/^(\w+?)e?\b/, '\1ing').tr('-', ' ')
  else
    $message = "compiling"
  end
end

EXEEXT = CONFIG['EXEEXT']
if CROSS_COMPILING
  $ruby = $mflags.defined?("MINIRUBY") || CONFIG['MINIRUBY']
elsif sep = config_string('BUILD_FILE_SEPARATOR')
  $ruby = "$(topdir:/=#{sep})#{sep}miniruby" + EXEEXT
else
  $ruby = '$(topdir)/miniruby' + EXEEXT
end
$ruby << " -I'$(topdir)'"
unless CROSS_COMPILING
  $ruby << " -I'$(top_srcdir)/lib'"
  $ruby << " -I'$(extout)/$(arch)' -I'$(extout)/common'" if $extout
  ENV["RUBYLIB"] = "-"
end
$mflags << "ruby=#$ruby"

MTIMES = [__FILE__, 'rbconfig.rb', srcdir+'/lib/mkmf.rb'].collect {|f| File.mtime(f)}

# get static-link modules
$static_ext = {}
if $extstatic
  $extstatic.each do |t|
    target = t
    target = target.downcase if File::FNM_SYSCASE.nonzero?
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
      target = target.downcase if File::FNM_SYSCASE.nonzero?
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
default_exclude_exts =
  case
  when $cygwin
    %w''
  when $mswin, $mingw
    %w'pty syslog'
  else
    %w'*win32*'
  end
withes, withouts = [["--with", nil], ["--without", default_exclude_exts]].collect {|w, d|
  if !(w = %w[-extensions -ext].collect {|o|arg_config(w+o)}).any?
    d ? proc {|c1| d.any?(&c1)} : proc {true}
  elsif (w = w.grep(String)).empty?
    proc {true}
  else
    w = w.collect {|o| o.split(/,/)}.flatten
    w.collect! {|o| o == '+' ? d : o}.flatten! if d
    proc {|c1| w.any?(&c1)}
  end
}
cond = proc {|ext, *|
  cond1 = proc {|n| File.fnmatch(n, ext)}
  withes.call(cond1) and !withouts.call(cond1)
}
($extension || %w[*]).each do |e|
  e = e.sub(/\A(?:\.\/)+/, '')
  exts |= Dir.glob("#{ext_prefix}/#{e}/**/extconf.rb").collect {|d|
    d = File.dirname(d)
    d.slice!(0, ext_prefix.length + 1)
    d
  }.find_all {|ext|
    with_config(ext, &cond)
  }.sort
  if $LIBRUBYARG_SHARED.empty? and CONFIG["EXTSTATIC"] == "static"
    exts.delete_if {|d| File.fnmatch?("-*", d)}
  end
end

if $extout
  extout = RbConfig.expand("#{$extout}", RbConfig::CONFIG.merge("topdir"=>$topdir))
  unless $ignore
    FileUtils.mkpath("#{extout}/gems")
  end
end

FileUtils.makedirs('gems')
ext_prefix = "#$top_srcdir/gems"
gems = Dir.glob(File.join(ext_prefix, ($extension || ''), '**/extconf.rb')).collect {|d|
  d = File.dirname(d)
  d.slice!(0, ext_prefix.length + 1)
  d
}.find_all {|ext|
  with_config(ext, &cond)
}.sort

extend Module.new {
  def timestamp_file(name, target_prefix = nil)
    super.sub(%r[/\.extout\.(?:-\.)?], '/.')
  end

  def configuration(srcdir)
    super << "EXTSO #{['=', $extso].join(' ')}\n"
  end
}

dir = Dir.pwd
FileUtils::makedirs('ext')
Dir::chdir('ext')

hdrdir = $hdrdir
$hdrdir = ($top_srcdir = relative_from(srcdir, $topdir = "..")) + "/include"
extso = []
fails = []
exts.each do |d|
  $static = $force_static ? true : $static_ext[d]

  if $ignore or !$nodynamic or $static
    result = extmake(d) or abort
    extso |= $extso
    fails << result unless result == true
  end
end

Dir.chdir('..')
FileUtils::makedirs('gems')
Dir.chdir('gems')
extout = $extout
unless gems.empty?
  def self.timestamp_file(name, target_prefix = nil)
    name = "$(arch)/gems/#{@gemname}#{target_prefix}" if name == '$(TARGET_SO_DIR)'
    super
  end

  def self.create_makefile(*args, &block)
    super(*args) do |conf|
      conf.find do |s|
        s.sub!(/^(TARGET_SO_DIR *= *)\$\(RUBYARCHDIR\)/) {
          "TARGET_GEM_DIR = $(extout)/gems/$(arch)/#{@gemname}\n"\
          "#{$1}$(TARGET_GEM_DIR)$(target_prefix)"
        }
      end
      conf.any? {|s| /^TARGET *= *\S/ =~ s} and conf << %{

# default target
all:

build_complete = $(TARGET_GEM_DIR)/gem.build_complete
install-so: build_complete
build_complete: $(build_complete)
$(build_complete): $(TARGET_SO)
	$(Q) $(TOUCH) $@

}
      conf
    end
  end
end
gems.each do |d|
  $extout = extout.dup
  @gemname = d[%r{\A[^/]+}]
  extmake(d, 'gems')
  extso |= $extso
end
$extout = extout
Dir.chdir('../ext')

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
$extobjs ||= []
$extpath ||= []
$extflags ||= ""
$extlibs ||= []
unless $extlist.empty?
  $extinit << "\n" unless $extinit.empty?
  list = $extlist.dup
  built = []
  while e = list.shift
    static, target, feature, required = e
    next unless static
    if required and !(required -= built).empty?
      l = list.size
      if (while l > 0; break true if required.include?(list[l-=1][1]) end)
        list.insert(l + 1, e)
      end
      next
    end
    base = File.basename(feature)
    $extinit << "    init(Init_#{base}, \"#{feature}.so\");\n"
    $extobjs << format("ext/%s/%s.%s", target, base, $LIBEXT)
    built << target
  end

  src = %{\
#include "ruby/ruby.h"

#define init(func, name) {	\\
    extern void func(void);	\\
    ruby_init_ext(name, func);	\\
}

void ruby_init_ext(const char *name, void (*init)(void));

void Init_ext(void)\n{\n#$extinit}
}
  if !modified?(extinit.c, MTIMES) || IO.read(extinit.c) != src
    open(extinit.c, "w") {|fe| fe.print src}
  end

  $extpath.delete("$(topdir)")
  $extflags = libpathflag($extpath) << " " << $extflags.strip
  conf = [
    ['LIBRUBY_SO_UPDATE', '$(LIBRUBY_EXTS)'],
    ['SETUP', $setup],
    ['EXTLIBS', $extlibs.join(' ')], ['EXTLDFLAGS', $extflags]
  ].map {|n, v|
    "#{n}=#{v}" if v &&= v[/\S(?:.*\S)?/]
  }.compact
  puts(*conf)
  $stdout.flush
  $mflags.concat(conf)
  $makeflags.concat(conf)
else
  FileUtils.rm_f(extinit.to_a)
end
rubies = []
%w[RUBY RUBYW STATIC_RUBY].each {|n|
  r = n
  if r = arg_config("--"+r.downcase) || config_string(r+"_INSTALL_NAME")
    rubies << RbConfig.expand(r+=EXEEXT)
    $mflags << "#{n}=#{r}"
  end
}

Dir.chdir ".."
unless $destdir.to_s.empty?
  $mflags.defined?("DESTDIR") or $mflags << "DESTDIR=#{$destdir}"
end
$makeflags.uniq!

$mflags.unshift("topdir=#$topdir")
ENV.delete("RUBYOPT")
if $configure_only and $command_output
  exts.map! {|d| "ext/#{d}/."}
  gems.map! {|d| "gems/#{d}/."}
  atomic_write_open($command_output) do |mf|
    mf.puts "V = 0"
    mf.puts "Q1 = $(V:1=)"
    mf.puts "Q = $(Q1:0=@)"
    mf.puts "ECHO1 = $(V:1=@:)"
    mf.puts "ECHO = $(ECHO1:0=@echo)"
    mf.puts "MFLAGS = -$(MAKEFLAGS)" if $nmake
    mf.puts

    def mf.macro(name, values, max = 70)
      print name, " ="
      w = w0 = name.size + 2
      h = " \\\n" + "\t" * (w / 8) + " " * (w % 8)
      values.each do |s|
        if s.size + w > max
          print h
          w = w0
        end
        print " ", s
        w += s.size + 1
      end
      puts
    end

    mf.macro "extensions", exts
    mf.macro "gems", gems
    mf.macro "EXTOBJS", $extlist.empty? ? ["dmyext.#{$OBJEXT}"] : ["ext/extinit.#{$OBJEXT}", *$extobjs]
    mf.macro "EXTLIBS", $extlibs
    mf.macro "EXTSO", extso
    mf.macro "EXTLDFLAGS", $extflags.split
    submakeopts = []
    if enable_config("shared", $enable_shared)
      submakeopts << 'DLDOBJS="$(EXTOBJS) $(EXTENCS)"'
      submakeopts << 'EXTOBJS='
      submakeopts << 'EXTSOLIBS="$(EXTLIBS)"'
      submakeopts << 'LIBRUBY_SO_UPDATE=$(LIBRUBY_EXTS)'
    else
      submakeopts << 'EXTOBJS="$(EXTOBJS) $(EXTENCS)"'
      submakeopts << 'EXTLIBS="$(EXTLIBS)"'
    end
    submakeopts << 'EXTLDFLAGS="$(EXTLDFLAGS)"'
    submakeopts << 'UPDATE_LIBRARIES="$(UPDATE_LIBRARIES)"'
    submakeopts << 'SHOWFLAGS='
    mf.macro "SUBMAKEOPTS", submakeopts
    mf.puts
    targets = %w[all install static install-so install-rb clean distclean realclean]
    targets.each do |tgt|
      mf.puts "#{tgt}: $(extensions:/.=/#{tgt})"
      mf.puts "#{tgt}: $(gems:/.=/#{tgt})" unless tgt == 'static'
      mf.puts "#{tgt}: note" unless /clean\z/ =~ tgt
    end
    mf.puts
    mf.puts "clean:\n\t-$(Q)$(RM) ext/extinit.#{$OBJEXT}"
    mf.puts "distclean:\n\t-$(Q)$(RM) ext/extinit.c"
    mf.puts
    mf.puts "#{rubies.join(' ')}: $(extensions:/.=/#{$force_static ? 'static' : 'all'}) $(gems:/.=/all)"
    submake = "$(Q)$(MAKE) $(MFLAGS) $(SUBMAKEOPTS)"
    mf.puts "all static: #{rubies.join(' ')}\n"
    $extobjs.each do |tgt|
      mf.puts "#{tgt}: #{File.dirname(tgt)}/static"
    end
    mf.puts "#{rubies.join(' ')}: $(EXTOBJS)#{' libencs' if CONFIG['ENCSTATIC'] == 'static'}"
    rubies.each do |tgt|
      mf.puts "#{tgt}:\n\t#{submake} $@"
    end
    mf.puts "libencs:\n\t$(Q)$(MAKE) -f enc.mk V=$(V) $@"
    mf.puts "ext/extinit.#{$OBJEXT}:\n\t$(Q)$(MAKE) $(MFLAGS) V=$(V) $@" if $static
    mf.puts
    if $gnumake == "yes"
      submake = "$(MAKE) -C $(@D)"
    else
      submake = "cd $(@D) && "
      config_string("exec") {|str| submake << str << " "}
      submake << "$(MAKE)"
    end
    gems = exts + gems
    targets.each do |tgt|
      (tgt == 'static' ? exts : gems).each do |d|
        mf.puts "#{d[0..-2]}#{tgt}:\n\t$(Q)#{submake} $(MFLAGS) V=$(V) $(@F)"
      end
    end
    mf.puts "\n""extso:\n"
    mf.puts "\t@echo EXTSO=$(EXTSO)"

    mf.puts "\n""note:\n"
    unless fails.empty?
      mf.puts %Q<\t@echo "*** Following extensions failed to configure:">
      fails.each do |d, n, err|
        d = "#{d}:#{n}:"
        if err
          d << " " << err
        end
        mf.puts %Q<\t@echo "#{d}">
      end
      mf.puts %Q<\t@echo "*** Fix the problems, then remove these directories and try again if you want.">
    end

  end
elsif $command_output
  message = "making #{rubies.join(', ')}"
  message = "echo #{message}"
  $mflags.concat(rubies)
  $makeflags.concat(rubies)
  cmd = $makeflags.map {|ss|ss.sub(/.*[$(){};\s].*/, %q['\&'])}.join(' ')
  open($command_output, 'wb') do |ff|
    case $command_output
    when /\.sh\z/
      ff.puts message, "rm -f \"$0\"; exec \"$@\" #{cmd}"
    when /\.bat\z/
      ["@echo off", message, "%* #{cmd}", "del %0 & exit %ERRORLEVEL%"].each do |ss|
        ff.print ss, "\r\n"
      end
    else
      ff.puts cmd
    end
    ff.chmod(0755)
  end
elsif !$configure_only
  message = "making #{rubies.join(', ')}"
  puts message
  $stdout.flush
  $mflags.concat(rubies)
  system($make, *$mflags) or exit($?.exitstatus)
end
# :startdoc:

#Local variables:
# mode: ruby
#end:
