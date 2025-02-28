#! /usr/local/bin/ruby
# -*- mode: ruby; coding: us-ascii -*-
# frozen_string_literal: false

module Gem; end # only needs Gem::Platform
require 'rubygems/platform'

# :stopdoc:
$extension = nil
$extstatic = nil
$force_static = nil
$destdir = nil
$dryrun = false
$nodynamic = nil
$extobjs = []
$extflags = ""
$extlibs = nil
$extpath = nil
$message = nil
$command_output = nil
$subconfigure = false

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
inplace = File.identical?($top_srcdir, $topdir)

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
  clean = false
  File.open(filename_new, "wbx") do |f|
    clean = true
    yield f
  end
  if File.binread(filename_new) != (File.binread(filename) rescue nil)
    File.rename(filename_new, filename)
    clean = false
  end
ensure
  if clean
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
    (old_srcs.split - srcs).empty? or return false
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

def create_makefile(target, srcprefix = nil)
  if $static and target.include?("/")
    base = File.basename(target)
    $defs << "-DInit_#{base}=Init_#{target.tr('/', '_')}"
  end
  super
end

def extmake(target, basedir = 'ext', maybestatic = true)
  FileUtils.mkpath target unless File.directory?(target)
  begin
    # don't build if parent library isn't build
    parent = true
    d = target
    until (d = File.dirname(d)) == '.'
      if File.exist?("#{$top_srcdir}/#{basedir}/#{d}/extconf.rb")
        parent = (/^all:\s*install/ =~ File.read("#{d}/Makefile") rescue false)
        break
      end
    end

    dir = Dir.pwd
    FileUtils.mkpath target unless File.directory?(target)
    Dir.chdir target
    top_srcdir = $top_srcdir
    topdir = $topdir
    hdrdir = $hdrdir
    prefix = "../" * (basedir.count("/")+target.count("/")+1)
    $top_srcdir = relative_from(top_srcdir, prefix)
    $hdrdir = relative_from(hdrdir, prefix)
    $topdir = prefix + $topdir
    $target = target
    $mdir = target
    $srcdir = File.join($top_srcdir, basedir, $mdir)
    $preload = nil
    $extso = []
    makefile = "./Makefile"
    static = $static
    $static = nil if noinstall = File.fnmatch?("-*", target)
    ok = parent && File.exist?(makefile)
    if parent
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
	old_objs = $objs || []
	old_cleanfiles = $distcleanfiles | $cleanfiles
	conf = ["#{$srcdir}/makefile.rb", "#{$srcdir}/extconf.rb"].find {|f| File.exist?(f)}
	if (!ok || ($extconf_h && !File.exist?($extconf_h)) ||
	    !(t = modified?(makefile, MTIMES)) ||
	    [conf, "#{$srcdir}/depend"].any? {|f| modified?(f, [t])})
        then
	  ok = false
          if verbose?
            print "#{conf}\n" if conf
          else
            print "#{$message} #{target}\n"
          end
          $stdout.flush
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

      message = nil
      if error
        loc = error.backtrace_locations[0]
        message = "#{loc.absolute_path}:#{loc.lineno}: #{error.message}"
        if Logging.log_opened?
          Logging::message("#{message}\n\t#{error.backtrace.join("\n\t")}\n")
        end
      end

      return [parent, message]
    end
    args = $mflags
    unless $destdir.to_s.empty? or $mflags.defined?("DESTDIR")
      args += ["DESTDIR=" + relative_from($destdir, "../"+prefix)]
    end
    $objs ||= []
    $srcs ||= []
    if $static and ok and !$objs.empty? and !noinstall
      args += ["static"]
      $extlist.push [(maybestatic ? $static : false), target, $target, $preload]
    end
    FileUtils.rm_f(old_cleanfiles - $distcleanfiles - $cleanfiles)
    FileUtils.rm_f(old_objs - $objs)
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
  $command_output or abort "--command-output option is mandatory"

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
  when /^(dist|real)?(clean)$/, /^install\b/
    abort "#{target} is obsolete"
  when /configure/
    $subconfigure = !ARGV.empty?
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
elsif CONFIG['EXTSTATIC']
  $ruby = '$(topdir)/miniruby' + EXEEXT
else
  $ruby = '$(topdir)/ruby' + EXEEXT
end
$ruby = [$ruby]
$ruby << "-I'$(topdir)'"
unless CROSS_COMPILING
  $ruby << "-I'$(top_srcdir)/lib'"
  $ruby << "-I'$(extout)/$(arch)'" << "-I'$(extout)/common'" if $extout
  ENV["RUBYLIB"] = "-"
end
topruby = $ruby
$ruby = topruby.join(' ')
$mflags << "ruby=#$ruby"
$builtruby = '$(topdir)/miniruby' + EXEEXT # Must be an executable path

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
  if (f = File.stat(setup) and f.file? rescue next)
    File.foreach(setup) do |line|
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
    break
  end
end unless $extstatic

@gemname = nil
if exts = ARGV.shift
  ext_prefix = exts[%r[\A(?>\.bundle/)?[^/]+(?:/(?=(.+)?)|\z)]]
  exts = $1
  $extension = [exts] if exts
  if ext_prefix.start_with?('.')
    @gemname = exts
  elsif exts
    $static_ext.delete_if {|t, *| !File.fnmatch(t, exts)}
  end
end
ext_prefix = "#{$top_srcdir}/#{ext_prefix || 'ext'}"
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
mandatory_exts = {}
withes, withouts = [["--with", nil], ["--without", default_exclude_exts]].collect {|w, d|
  if !(w = %w[-extensions -ext].collect {|o|arg_config(w+o)}).any?
    d ? proc {|c1| d.any?(&c1)} : proc {true}
  elsif (w = w.grep(String)).empty?
    proc {true}
  else
    w = w.collect {|o| o.split(/,/)}.flatten
    w.collect! {|o| o == '+' ? d : o}.flatten!
    proc {|c1| w.any?(&c1)}
  end
}
cond = proc {|ext, *|
  withes.call(proc {|n|
                !n or (mandatory_exts[ext] = true if File.fnmatch(n, ext))
              }) and
    !withouts.call(proc {|n| File.fnmatch(n, ext)})
}
($extension || %w[*]).each do |e|
  e = e.sub(/\A(?:\.\/)+/, '')
  incl, excl = Dir.glob("#{ext_prefix}/#{e}/**/extconf.rb").collect {|d|
    d = File.dirname(d)
    d.slice!(0, ext_prefix.length + 1)
    d
  }.partition {|ext|
    with_config(ext, &cond)
  }
  incl.sort!
  excl.sort!.collect! {|d| d+"/"}
  nil while incl.reject! {|d| excl << d+"/" if excl.any? {|x| d.start_with?(x)}}
  exts |= incl
  if $LIBRUBYARG_SHARED.empty? and CONFIG["EXTSTATIC"] == "static"
    exts.delete_if {|d| File.fnmatch?("-*", d)}
  end
end
ext_prefix = ext_prefix[$top_srcdir.size+1..-2]

@ext_prefix = ext_prefix
@inplace = inplace
extend Module.new {

  def timestamp_file(name, target_prefix = nil)
    if @gemname and name == '$(TARGET_SO_DIR)'
      gem = true
      name = "$(gem_platform)/$(ruby_version)/gems/#{@gemname}#{target_prefix}"
    end
    path = super.sub(%r[/\.extout\.(?:-\.)?], '/.')
    if gem
      nil while path.sub!(%r[/\.(gem_platform|ruby_version)\.-(?=\.)], '/$(\1)/')
    end
    path
  end

  def configuration(srcdir)
    super << "EXTSO #{['=', $extso].join(' ')}\n"
  end

  def create_makefile(*args, &block)
    unless @gemname
      if $static and (target = args.first).include?("/")
        base = File.basename(target)
        $defs << "-DInit_#{base}=Init_#{target.tr('/', '_')}"
      end
      return super
    end
    super(*args) do |conf|
      conf.find do |s|
        s.sub!(%r(^(srcdir *= *)\$\(top_srcdir\)/\.bundle/gems/[^/]+(?=/))) {
          "gem_#{$&}\n" "#{$1}$(gem_srcdir)"
        }
        s.sub!(/^(TIMESTAMP_DIR *= *)\$\(extout\)/) {
          "TARGET_TOPDIR = $(topdir)/.bundle\n" "#{$1}$(TARGET_TOPDIR)"
        }
        s.sub!(/^(TARGET_SO_DIR *= *)\$\(RUBYARCHDIR\)/) {
          "TARGET_GEM_DIR = $(TARGET_TOPDIR)/extensions/$(gem_platform)"\
          "/$(ruby_version)#{$enable_shared ? '' : '-static'}/#{@gemname}\n"\
          "#{$1}$(TARGET_GEM_DIR)$(target_prefix)"
        }
      end

      gemlib = File.directory?("#{$top_srcdir}/#{@ext_prefix}/#{@gemname}/lib")
      if conf.any? {|s| /^TARGET *= *\S/ =~ s}
        conf << %{
gem_platform = #{Gem::Platform.local}

# default target
all:

gem = #{@gemname}

build_complete = $(TARGET_GEM_DIR)/gem.build_complete
install-so: build_complete
clean-so:: clean-build_complete

build_complete: $(build_complete)
$(build_complete): $(TARGET_SO)
	$(Q) $(TOUCH) $@

clean-build_complete:
	-$(Q)$(RM) $(build_complete)

install: gemspec
clean: clean-gemspec

gemspec = $(TARGET_TOPDIR)/specifications/$(gem).gemspec
$(gemspec): $(gem_srcdir)/.bundled.$(gem).gemspec
	$(Q) $(MAKEDIRS) $(@D)
	$(Q) $(COPY) $(gem_srcdir)/.bundled.$(gem).gemspec $@

gemspec: $(gemspec)

clean-gemspec:
	-$(Q)$(RM) $(gemspec)
}

        if gemlib
          conf << %{
install-rb: gemlib
clean-rb:: clean-gemlib

LN_S = #{config_string('LN_S')}
CP_R = #{config_string('CP')} -r

gemlib = $(TARGET_TOPDIR)/gems/$(gem)/lib
gemlib:#{%{ $(gemlib)\n$(gemlib): $(gem_srcdir)/lib} if $nmake}
	$(Q) #{@inplace ? '$(NULLCMD) ' : ''}$(RUBY) $(top_srcdir)/tool/ln_sr.rb -q -f -T $(gem_srcdir)/lib $(gemlib)

clean-gemlib:
	$(Q) $(#{@inplace ? 'NULLCMD' : 'RM_RF'}) $(gemlib)
}
        end
      end

      conf
    end
  end
}

dir = Dir.pwd
FileUtils::makedirs(ext_prefix)
Dir::chdir(ext_prefix)

hdrdir = $hdrdir
$hdrdir = ($top_srcdir = relative_from(srcdir, $topdir = "..")) + "/include"
extso = []
fails = []
exts.each do |d|
  $static = $force_static ? true : $static_ext[d]

  if !$nodynamic or $static
    result = extmake(d, ext_prefix, !@gemname) or abort
    extso |= $extso
    fails << [d, result] unless result == true
  end
end

$top_srcdir = srcdir
$topdir = "."
$hdrdir = hdrdir

extinit = Struct.new(:c, :o) {
  def initialize(src)
    super("#{src}.c", "#{src}.#{$OBJEXT}")
  end
}.new("extinit")

$extobjs ||= []
$extpath ||= []
$extflags ||= ""
$extlibs ||= []
extinits = []
unless $extlist.empty?
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
    extinits << feature
    $extobjs << format("ext/%s/%s.%s", target, base, $LIBEXT)
    built << target
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
  puts(*conf) unless $subconfigure
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

Dir.chdir dir
unless $destdir.to_s.empty?
  $mflags.defined?("DESTDIR") or $mflags << "DESTDIR=#{$destdir}"
end
$makeflags.uniq!

$mflags.unshift("topdir=#$topdir")
ENV.delete("RUBYOPT")
exts.map! {|d| "#{ext_prefix}/#{d}/."}
FileUtils.makedirs(File.dirname($command_output))
begin
  atomic_write_open($command_output) do |mf|
    mf.puts "V = 0"
    mf.puts "V0 = $(V:0=)"
    mf.puts "Q1 = $(V:1=)"
    mf.puts "Q = $(Q1:0=@)"
    mf.puts "ECHO1 = $(V:1=@:)"
    mf.puts "ECHO = $(ECHO1:0=@echo)"
    mf.puts "MFLAGS = -$(MAKEFLAGS)" if $nmake
    mf.puts "override MFLAGS := $(filter-out -j%,$(MFLAGS))" if $gnumake
    mf.puts "ext_build_dir = #{File.dirname($command_output)}"
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

    mf.macro "ruby", topruby
    mf.macro "RUBY", ["$(ruby)"]
    mf.macro "extensions", exts
    mf.macro "EXTOBJS", $extlist.empty? ? ["dmyext.#{$OBJEXT}"] : ["ext/extinit.#{$OBJEXT}", *$extobjs]
    mf.macro "EXTLIBS", $extlibs
    mf.macro "EXTSO", extso
    mf.macro "EXTLDFLAGS", $extflags.split
    mf.macro "EXTINITS", extinits
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
    submakeopts << 'EXTINITS="$(EXTINITS)"'
    submakeopts << 'UPDATE_LIBRARIES="$(UPDATE_LIBRARIES)"'
    submakeopts << 'SHOWFLAGS='
    mf.macro "SUBMAKEOPTS", submakeopts
    mf.macro "NOTE_MESG", %w[$(RUBY) $(top_srcdir)/tool/lib/colorize.rb skip]
    mf.macro "NOTE_NAME", %w[$(RUBY) $(top_srcdir)/tool/lib/colorize.rb fail]
    %w[RM RMDIRS RMDIR RMALL].each {|w| mf.macro w, [RbConfig::CONFIG[w]]}
    mf.puts
    targets = %w[all install static install-so install-rb clean distclean realclean]
    targets.each do |tgt|
      mf.puts "#{tgt}: $(extensions:/.=/#{tgt})"
      mf.puts "#{tgt}: note" unless /clean\z/ =~ tgt
    end
    mf.puts
    mf.puts "clean:\n\t-$(Q)$(RM) ext/extinit.#{$OBJEXT}"
    mf.puts "distclean:\n\t-$(Q)$(RM) ext/extinit.c"
    mf.puts
    mf.puts "#{rubies.join(' ')}: $(extensions:/.=/#{$force_static ? 'static' : 'all'})"
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
    mf.puts "ext/extinit.#{$OBJEXT}:\n\t$(Q)$(MAKE) $(MFLAGS) V=$(V) EXTINITS=\"$(EXTINITS)\" $@" if $static
    mf.puts
    if $gnumake == "yes"
      submake = "$(MAKE) -C $(@D)"
    else
      submake = "cd $(@D) && "
      config_string("exec") {|str| submake << str << " "}
      submake << "$(MAKE)"
    end
    targets.each do |tgt|
      exts.each do |d|
        d = d[0..-2]
        t = "#{d}#{tgt}"
        if clean = /^(dist|real)?clean$/.match(tgt)
          deps = exts.select {|e|e.start_with?(d)}.map {|e|"#{e[0..-2]}#{tgt}"} - [t]
          pd = [' clean-local', *deps].join(' ')
        else
          pext = File.dirname(d)
          pd = " #{pext}/#{tgt}" if exts.include?("#{pext}/.")
        end
        mf.puts "#{t}:#{pd}\n\t$(Q)#{submake} $(MFLAGS) V=$(V) $(@F)"
        if clean and clean.begin(1)
          mf.puts "\t$(Q)$(RM) $(ext_build_dir)/exts.mk\n\t$(Q)$(RMDIRS) -p $(@D)"
        end
      end
    end
    mf.puts "\n""clean-local:\n\t$(Q)$(RM) $(ext_build_dir)/*~ $(ext_build_dir)/*.bak $(ext_build_dir)/core"
    mf.puts "\n""extso:\n"
    mf.puts "\t@echo EXTSO=$(EXTSO)"

    mf.puts "\n""note:\n"
    unless fails.empty?
      abandon = false
      mf.puts "note: note-body\n"
      mf.puts "note-body:: note-header\n"
      mf.puts "note-header:\n"
      mf.puts %Q<\t@$(NOTE_MESG) "*** Following extensions are not compiled:">
      mf.puts "note-body:: note-header\n"
      fails.each do |ext, (parent, err)|
        abandon ||= mandatory_exts[ext]
        mf.puts %Q<\t@$(NOTE_NAME) "#{ext}:">
        if parent
          mf.puts %Q<\t@echo "\tCould not be configured. It will not be installed.">
          err and err.scan(/.+/) do |ee|
            mf.puts %Q<\t@echo "\t#{ee.gsub(/["`$^]/, '\\\\\\&')}">
          end
          mf.puts %Q<\t@echo "\tCheck #{ext_prefix}/#{ext}/mkmf.log for more details.">
        else
          mf.puts %Q<\t@echo "\tSkipped because its parent was not configured.">
        end
      end
      mf.puts "note:\n"
      mf.puts %Q<\t@$(NOTE_MESG) "*** Fix the problems, then remove these directories and try again if you want.">
      if abandon
        mf.puts "\t""@exit 1"
      end
    end
  end
end
# :startdoc:

#Local variables:
# mode: ruby
#end:
