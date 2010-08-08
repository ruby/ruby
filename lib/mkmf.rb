# -*- indent-tabs-mode: t -*-
# module to create Makefile for extension modules
# invoke like: ruby -r mkmf extconf.rb

require 'rbconfig'
require 'fileutils'
require 'shellwords'

CONFIG = RbConfig::MAKEFILE_CONFIG
ORIG_LIBPATH = ENV['LIB']

CXX_EXT = %w[cc cxx cpp]
if File::FNM_SYSCASE.zero?
  CXX_EXT.concat(%w[C])
end
SRC_EXT = %w[c m].concat(CXX_EXT)
$static = nil
$config_h = '$(arch_hdrdir)/ruby/config.h'
$default_static = $static

unless defined? $configure_args
  $configure_args = {}
  args = CONFIG["configure_args"]
  if ENV["CONFIGURE_ARGS"]
    args << " " << ENV["CONFIGURE_ARGS"]
  end
  for arg in Shellwords::shellwords(args)
    arg, val = arg.split('=', 2)
    next unless arg
    arg.tr!('_', '-')
    if arg.sub!(/^(?!--)/, '--')
      val or next
      arg.downcase!
    end
    next if /^--(?:top|topsrc|src|cur)dir$/ =~ arg
    $configure_args[arg] = val || true
  end
  for arg in ARGV
    arg, val = arg.split('=', 2)
    next unless arg
    arg.tr!('_', '-')
    if arg.sub!(/^(?!--)/, '--')
      val or next
      arg.downcase!
    end
    $configure_args[arg] = val || true
  end
end

$libdir = CONFIG["libdir"]
$rubylibdir = CONFIG["rubylibdir"]
$archdir = CONFIG["archdir"]
$sitedir = CONFIG["sitedir"]
$sitelibdir = CONFIG["sitelibdir"]
$sitearchdir = CONFIG["sitearchdir"]
$vendordir = CONFIG["vendordir"]
$vendorlibdir = CONFIG["vendorlibdir"]
$vendorarchdir = CONFIG["vendorarchdir"]

$mswin = /mswin/ =~ RUBY_PLATFORM
$bccwin = /bccwin/ =~ RUBY_PLATFORM
$mingw = /mingw/ =~ RUBY_PLATFORM
$cygwin = /cygwin/ =~ RUBY_PLATFORM
$netbsd = /netbsd/ =~ RUBY_PLATFORM
$os2 = /os2/ =~ RUBY_PLATFORM
$beos = /beos/ =~ RUBY_PLATFORM
$haiku = /haiku/ =~ RUBY_PLATFORM
$solaris = /solaris/ =~ RUBY_PLATFORM
$universal = /universal/ =~ RUBY_PLATFORM
$dest_prefix_pattern = (File::PATH_SEPARATOR == ';' ? /\A([[:alpha:]]:)?/ : /\A/)

# :stopdoc:

def config_string(key, config = CONFIG)
  s = config[key] and !s.empty? and block_given? ? yield(s) : s
end

def dir_re(dir)
  Regexp.new('\$(?:\('+dir+'\)|\{'+dir+'\})(?:\$(?:\(target_prefix\)|\{target_prefix\}))?')
end

def relative_from(path, base)
  dir = File.join(path, "")
  if File.expand_path(dir) == File.expand_path(dir, base)
    path
  else
    File.join(base, path)
  end
end

INSTALL_DIRS = [
  [dir_re('commondir'), "$(RUBYCOMMONDIR)"],
  [dir_re('sitedir'), "$(RUBYCOMMONDIR)"],
  [dir_re('vendordir'), "$(RUBYCOMMONDIR)"],
  [dir_re('rubylibdir'), "$(RUBYLIBDIR)"],
  [dir_re('archdir'), "$(RUBYARCHDIR)"],
  [dir_re('sitelibdir'), "$(RUBYLIBDIR)"],
  [dir_re('vendorlibdir'), "$(RUBYLIBDIR)"],
  [dir_re('sitearchdir'), "$(RUBYARCHDIR)"],
  [dir_re('vendorarchdir'), "$(RUBYARCHDIR)"],
  [dir_re('rubyhdrdir'), "$(RUBYHDRDIR)"],
  [dir_re('sitehdrdir'), "$(SITEHDRDIR)"],
  [dir_re('vendorhdrdir'), "$(VENDORHDRDIR)"],
  [dir_re('bindir'), "$(BINDIR)"],
]

def install_dirs(target_prefix = nil)
  if $extout
    dirs = [
      ['BINDIR',        '$(extout)/bin'],
      ['RUBYCOMMONDIR', '$(extout)/common'],
      ['RUBYLIBDIR',    '$(RUBYCOMMONDIR)$(target_prefix)'],
      ['RUBYARCHDIR',   '$(extout)/$(arch)$(target_prefix)'],
      ['HDRDIR',        '$(extout)/include/ruby$(target_prefix)'],
      ['ARCHHDRDIR',    '$(extout)/include/$(arch)/ruby$(target_prefix)'],
      ['extout',        "#$extout"],
      ['extout_prefix', "#$extout_prefix"],
    ]
  elsif $extmk
    dirs = [
      ['BINDIR',        '$(bindir)'],
      ['RUBYCOMMONDIR', '$(rubylibdir)'],
      ['RUBYLIBDIR',    '$(rubylibdir)$(target_prefix)'],
      ['RUBYARCHDIR',   '$(archdir)$(target_prefix)'],
      ['HDRDIR',        '$(rubyhdrdir)/ruby$(target_prefix)'],
      ['ARCHHDRDIR',    '$(rubyhdrdir)/$(arch)/ruby$(target_prefix)'],
    ]
  elsif $configure_args.has_key?('--vendor')
    dirs = [
      ['BINDIR',        '$(bindir)'],
      ['RUBYCOMMONDIR', '$(vendordir)$(target_prefix)'],
      ['RUBYLIBDIR',    '$(vendorlibdir)$(target_prefix)'],
      ['RUBYARCHDIR',   '$(vendorarchdir)$(target_prefix)'],
      ['HDRDIR',        '$(rubyhdrdir)/ruby$(target_prefix)'],
      ['ARCHHDRDIR',    '$(rubyhdrdir)/$(arch)/ruby$(target_prefix)'],
    ]
  else
    dirs = [
      ['BINDIR',        '$(bindir)'],
      ['RUBYCOMMONDIR', '$(sitedir)$(target_prefix)'],
      ['RUBYLIBDIR',    '$(sitelibdir)$(target_prefix)'],
      ['RUBYARCHDIR',   '$(sitearchdir)$(target_prefix)'],
      ['HDRDIR',        '$(rubyhdrdir)/ruby$(target_prefix)'],
      ['ARCHHDRDIR',    '$(rubyhdrdir)/$(arch)/ruby$(target_prefix)'],
    ]
  end
  dirs << ['target_prefix', (target_prefix ? "/#{target_prefix}" : "")]
  dirs
end

def map_dir(dir, map = nil)
  map ||= INSTALL_DIRS
  map.inject(dir) {|d, (orig, new)| d.gsub(orig, new)}
end

topdir = File.dirname(File.dirname(__FILE__))
path = File.expand_path($0)
$extmk = path[0, topdir.size+1] == topdir+"/"
$extmk &&= %r"\A(?:ext|enc|tool|test(?:/.+))\z" =~ File.dirname(path[topdir.size+1..-1])
$extmk &&= true
if not $extmk and File.exist?(($hdrdir = RbConfig::CONFIG["rubyhdrdir"]) + "/ruby/ruby.h")
  $topdir = $hdrdir
  $top_srcdir = $hdrdir
  $arch_hdrdir = $hdrdir + "/$(arch)"
elsif File.exist?(($hdrdir = ($top_srcdir ||= topdir) + "/include")  + "/ruby.h")
  $topdir ||= RbConfig::CONFIG["topdir"]
  $arch_hdrdir = "$(extout)/include/$(arch)"
else
  abort "mkmf.rb can't find header files for ruby at #{$hdrdir}/ruby.h"
end

OUTFLAG = CONFIG['OUTFLAG']
COUTFLAG = CONFIG['COUTFLAG']
CPPOUTFILE = CONFIG['CPPOUTFILE']

CONFTEST_C = "conftest.c".freeze

class String
  # Wraps a string in escaped quotes if it contains whitespace.
  def quote
    /\s/ =~ self ? "\"#{self}\"" : "#{self}"
  end

  # Generates a string used as cpp macro name.
  def tr_cpp
    strip.upcase.tr_s("^A-Z0-9_", "_")
  end
end
class Array
  # Wraps all strings in escaped quotes if they contain whitespace.
  def quote
    map {|s| s.quote}
  end
end

def rm_f(*files)
  opt = (Hash === files.last ? [files.pop] : [])
  FileUtils.rm_f(Dir[*files.flatten], *opt)
end

def rm_rf(*files)
  opt = (Hash === files.last ? [files.pop] : [])
  FileUtils.rm_rf(Dir[*files.flatten], *opt)
end

# Returns time stamp of the +target+ file if it exists and is newer
# than or equal to all of +times+.
def modified?(target, times)
  (t = File.mtime(target)) rescue return nil
  Array === times or times = [times]
  t if times.all? {|n| n <= t}
end

def merge_libs(*libs)
  libs.inject([]) do |x, y|
    xy = x & y
    xn = yn = 0
    y = y.inject([]) {|ary, e| ary.last == e ? ary : ary << e}
    y.each_with_index do |v, yi|
      if xy.include?(v)
        xi = [x.index(v), xn].max()
        x[xi, 1] = y[yn..yi]
        xn, yn = xi + (yi - yn + 1), yi + 1
      end
    end
    x.concat(y[yn..-1] || [])
  end
end

# This is a custom logging module. It generates an mkmf.log file when you
# run your extconf.rb script. This can be useful for debugging unexpected
# failures.
#
# This module and its associated methods are meant for internal use only.
#
module Logging
  @log = nil
  @logfile = 'mkmf.log'
  @orgerr = $stderr.dup
  @orgout = $stdout.dup
  @postpone = 0
  @quiet = $extmk

  def self::log_open
    @log ||= File::open(@logfile, 'wb')
    @log.sync = true
  end

  def self::open
    log_open
    $stderr.reopen(@log)
    $stdout.reopen(@log)
    yield
  ensure
    $stderr.reopen(@orgerr)
    $stdout.reopen(@orgout)
  end

  def self::message(*s)
    log_open
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

  def self::postpone
    tmplog = "mkmftmp#{@postpone += 1}.log"
    open do
      log, *save = @log, @logfile, @orgout, @orgerr
      @log, @logfile, @orgout, @orgerr = nil, tmplog, log, log
      begin
        log.print(open {yield})
      ensure
        @log.close
        File::open(tmplog) {|t| FileUtils.copy_stream(t, log)}
        @log, @logfile, @orgout, @orgerr = log, *save
        @postpone -= 1
        rm_f tmplog
      end
    end
  end

  class << self
    attr_accessor :quiet
  end
end

def xsystem command
  varpat = /\$\((\w+)\)|\$\{(\w+)\}/
  if varpat =~ command
    vars = Hash.new {|h, k| h[k] = ''; ENV[k]}
    command = command.dup
    nil while command.gsub!(varpat) {vars[$1||$2]}
  end
  Logging::open do
    puts command.quote
    system(command)
  end
end

def xpopen command, *mode, &block
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
  src = src.split(/^/)
  fmt = "%#{src.size.to_s.size}d: %s"
  Logging::message <<"EOM"
checked program was:
/* begin */
EOM
  src.each_with_index {|line, no| Logging::message fmt, no+1, line}
  Logging::message <<"EOM"
/* end */

EOM
end

def create_tmpsrc(src)
  src = "#{COMMON_HEADERS}\n#{src}"
  src = yield(src) if block_given?
  src.gsub!(/[ \t]+$/, '')
  src.gsub!(/\A\n+|^\n+$/, '')
  src.sub!(/[^\n]\z/, "\\&\n")
  count = 0
  begin
    open(CONFTEST_C, "wb") do |cfile|
      cfile.print src
    end
  rescue Errno::EACCES
    if (count += 1) < 5
      sleep 0.2
      retry
    end
  end
  src
end

def have_devel?
  unless defined? $have_devel
    $have_devel = true
    $have_devel = try_link(MAIN_DOES_NOTHING)
  end
  $have_devel
end

def try_do(src, command, &b)
  unless have_devel?
    raise <<MSG
The complier failed to generate an executable file.
You have to install development tools first.
MSG
  end
  begin
    src = create_tmpsrc(src, &b)
    xsystem(command)
  ensure
    log_src(src)
    rm_rf 'conftest.dSYM'
  end
end

def link_command(ldflags, opt="", libpath=$DEFLIBPATH|$LIBPATH)
  conf = RbConfig::CONFIG.merge('hdrdir' => $hdrdir.quote,
                                'src' => "#{CONFTEST_C}",
                                'arch_hdrdir' => "#$arch_hdrdir",
                                'top_srcdir' => $top_srcdir.quote,
                                'INCFLAGS' => "#$INCFLAGS",
                                'CPPFLAGS' => "#$CPPFLAGS",
                                'CFLAGS' => "#$CFLAGS",
                                'ARCH_FLAG' => "#$ARCH_FLAG",
                                'LDFLAGS' => "#$LDFLAGS #{ldflags}",
                                'LIBPATH' => libpathflag(libpath),
                                'LOCAL_LIBS' => "#$LOCAL_LIBS #$libs",
                                'LIBS' => "#$LIBRUBYARG_STATIC #{opt} #$LIBS")
  RbConfig::expand(TRY_LINK.dup, conf)
end

def cc_command(opt="")
  conf = RbConfig::CONFIG.merge('hdrdir' => $hdrdir.quote, 'srcdir' => $srcdir.quote,
                                'arch_hdrdir' => "#$arch_hdrdir",
                                'top_srcdir' => $top_srcdir.quote)
  RbConfig::expand("$(CC) #$INCFLAGS #$CPPFLAGS #$CFLAGS #$ARCH_FLAG #{opt} -c #{CONFTEST_C}",
		   conf)
end

def cpp_command(outfile, opt="")
  conf = RbConfig::CONFIG.merge('hdrdir' => $hdrdir.quote, 'srcdir' => $srcdir.quote,
                                'arch_hdrdir' => "#$arch_hdrdir",
                                'top_srcdir' => $top_srcdir.quote)
  RbConfig::expand("$(CPP) #$INCFLAGS #$CPPFLAGS #$CFLAGS #{opt} #{CONFTEST_C} #{outfile}",
		   conf)
end

def libpathflag(libpath=$DEFLIBPATH|$LIBPATH)
  libpath.map{|x|
    case x
    when "$(topdir)", /\A\./
      LIBPATHFLAG
    else
      LIBPATHFLAG+RPATHFLAG
    end % x.quote
  }.join
end

def try_link0(src, opt="", &b)
  cmd = link_command("", opt)
  if $universal
    require 'tmpdir'
    Dir.mktmpdir("mkmf_", oldtmpdir = ENV["TMPDIR"]) do |tmpdir|
      begin
        ENV["TMPDIR"] = tmpdir
        try_do(src, cmd, &b)
      ensure
        ENV["TMPDIR"] = oldtmpdir
      end
    end
  else
    try_do(src, cmd, &b)
  end
end

def try_link(src, opt="", &b)
  try_link0(src, opt, &b)
ensure
  rm_f "conftest*", "c0x32*"
end

def try_compile(src, opt="", &b)
  try_do(src, cc_command(opt), &b)
ensure
  rm_f "conftest*"
end

def try_cpp(src, opt="", &b)
  try_do(src, cpp_command(CPPOUTFILE, opt), &b)
ensure
  rm_f "conftest*"
end

class Object
  alias_method :try_header, (config_string('try_header') || :try_cpp)
end

def cpp_include(header)
  if header
    header = [header] unless header.kind_of? Array
    header.map {|h| String === h ? "#include <#{h}>\n" : h}.join
  else
    ""
  end
end

def with_cppflags(flags)
  cppflags = $CPPFLAGS
  $CPPFLAGS = flags
  ret = yield
ensure
  $CPPFLAGS = cppflags unless ret
end

def with_cflags(flags)
  cflags = $CFLAGS
  $CFLAGS = flags
  ret = yield
ensure
  $CFLAGS = cflags unless ret
end

def with_ldflags(flags)
  ldflags = $LDFLAGS
  $LDFLAGS = flags
  ret = yield
ensure
  $LDFLAGS = ldflags unless ret
end

def try_static_assert(expr, headers = nil, opt = "", &b)
  headers = cpp_include(headers)
  try_compile(<<SRC, opt, &b)
#{headers}
/*top*/
int conftest_const[(#{expr}) ? 1 : -1];
SRC
end

def try_constant(const, headers = nil, opt = "", &b)
  includes = cpp_include(headers)
  if CROSS_COMPILING
    if try_static_assert("#{const} > 0", headers, opt)
      # positive constant
    elsif try_static_assert("#{const} < 0", headers, opt)
      neg = true
      const = "-(#{const})"
    elsif try_static_assert("#{const} == 0", headers, opt)
      return 0
    else
      # not a constant
      return nil
    end
    upper = 1
    lower = 0
    until try_static_assert("#{const} <= #{upper}", headers, opt)
      lower = upper
      upper <<= 1
    end
    return nil unless lower
    while upper > lower + 1
      mid = (upper + lower) / 2
      if try_static_assert("#{const} > #{mid}", headers, opt)
        lower = mid
      else
        upper = mid
      end
    end
    upper = -upper if neg
    return upper
  else
    src = %{#{includes}
#include <stdio.h>
/*top*/
int conftest_const = (int)(#{const});
int main() {printf("%d\\n", conftest_const); return 0;}
}
    if try_link0(src, opt, &b)
      xpopen("./conftest") do |f|
        return Integer(f.gets)
      end
    end
  end
  nil
end

def try_func(func, libs, headers = nil, &b)
  headers = cpp_include(headers)
  try_link(<<"SRC", libs, &b) or
#{headers}
/*top*/
#{MAIN_DOES_NOTHING}
int t() { void ((*volatile p)()); p = (void ((*)()))#{func}; return 0; }
SRC
  try_link(<<"SRC", libs, &b)
#{headers}
/*top*/
#{MAIN_DOES_NOTHING}
int t() { #{func}(); return 0; }
SRC
end

def try_var(var, headers = nil, &b)
  headers = cpp_include(headers)
  try_compile(<<"SRC", &b)
#{headers}
/*top*/
#{MAIN_DOES_NOTHING}
int t() { const volatile void *volatile p; p = &(&#{var})[0]; return 0; }
SRC
end

def egrep_cpp(pat, src, opt = "", &b)
  src = create_tmpsrc(src, &b)
  xpopen(cpp_command('', opt)) do |f|
    if Regexp === pat
      puts("    ruby -ne 'print if #{pat.inspect}'")
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

# This is used internally by the have_macro? method.
def macro_defined?(macro, src, opt = "", &b)
  src = src.sub(/[^\n]\z/, "\\&\n")
  try_compile(src + <<"SRC", opt, &b)
/*top*/
#ifndef #{macro}
# error
>>>>>> #{macro} undefined <<<<<<
#endif
SRC
end

def try_run(src, opt = "", &b)
  if try_link0(src, opt, &b)
    xsystem("./conftest")
  else
    nil
  end
ensure
  rm_f "conftest*"
end

def install_files(mfile, ifiles, map = nil, srcprefix = nil)
  ifiles or return
  ifiles.empty? and return
  srcprefix ||= "$(srcdir)/#{srcprefix}".chomp('/')
  RbConfig::expand(srcdir = srcprefix.dup)
  dirs = []
  path = Hash.new {|h, i| h[i] = dirs.push([i])[-1]}
  ifiles.each do |files, dir, prefix|
    dir = map_dir(dir, map)
    prefix &&= %r|\A#{Regexp.quote(prefix)}/?|
    if /\A\.\// =~ files
      # install files which are in current working directory.
      files = files[2..-1]
      len = nil
    else
      # install files which are under the $(srcdir).
      files = File.join(srcdir, files)
      len = srcdir.size
    end
    f = nil
    Dir.glob(files) do |fx|
      f = fx
      f[0..len] = "" if len
      case File.basename(f)
      when *$NONINSTALLFILES
        next
      end
      d = File.dirname(f)
      d.sub!(prefix, "") if prefix
      d = (d.empty? || d == ".") ? dir : File.join(dir, d)
      f = File.join(srcprefix, f) if len
      path[d] << f
    end
    unless len or f
      d = File.dirname(files)
      d.sub!(prefix, "") if prefix
      d = (d.empty? || d == ".") ? dir : File.join(dir, d)
      path[d] << files
    end
  end
  dirs
end

def install_rb(mfile, dest, srcdir = nil)
  install_files(mfile, [["lib/**/*.rb", dest, "lib"]], nil, srcdir)
end

def append_library(libs, lib) # :no-doc:
  format(LIBARG, lib) + " " + libs
end

def message(*s)
  unless Logging.quiet and not $VERBOSE
    printf(*s)
    $stdout.flush
  end
end

# This emits a string to stdout that allows users to see the results of the
# various have* and find* methods as they are tested.
#
# Internal use only.
#
def checking_for(m, fmt = nil)
  f = caller[0][/in `([^<].*)'$/, 1] and f << ": " #` for vim #'
  m = "checking #{/\Acheck/ =~ f ? '' : 'for '}#{m}... "
  message "%s", m
  a = r = nil
  Logging::postpone do
    r = yield
    a = (fmt ? fmt % r : r ? "yes" : "no") << "\n"
    "#{f}#{m}-------------------- #{a}\n"
  end
  message(a)
  Logging::message "--------------------\n\n"
  r
end

def checking_message(target, place = nil, opt = nil)
  [["in", place], ["with", opt]].inject("#{target}") do |msg, (pre, noun)|
    if noun
      [[:to_str], [:join, ","], [:to_s]].each do |meth, *args|
        if noun.respond_to?(meth)
          break noun = noun.send(meth, *args)
        end
      end
      msg << " #{pre} #{noun}" unless noun.empty?
    end
    msg
  end
end

# :startdoc:

# Returns whether or not +macro+ is defined either in the common header
# files or within any +headers+ you provide.
#
# Any options you pass to +opt+ are passed along to the compiler.
#
def have_macro(macro, headers = nil, opt = "", &b)
  checking_for checking_message(macro, headers, opt) do
    macro_defined?(macro, cpp_include(headers), opt, &b)
  end
end

# Returns whether or not the given entry point +func+ can be found within
# +lib+.  If +func+ is nil, the 'main()' entry point is used by default.
# If found, it adds the library to list of libraries to be used when linking
# your extension.
#
# If +headers+ are provided, it will include those header files as the
# header files it looks in when searching for +func+.
#
# The real name of the library to be linked can be altered by
# '--with-FOOlib' configuration option.
#
def have_library(lib, func = nil, headers = nil, &b)
  func = "main" if !func or func.empty?
  lib = with_config(lib+'lib', lib)
  checking_for checking_message("#{func}()", LIBARG%lib) do
    if COMMON_LIBS.include?(lib)
      true
    else
      libs = append_library($libs, lib)
      if try_func(func, libs, headers, &b)
        $libs = libs
        true
      else
        false
      end
    end
  end
end

# Returns whether or not the entry point +func+ can be found within the library
# +lib+ in one of the +paths+ specified, where +paths+ is an array of strings.
# If +func+ is nil , then the main() function is used as the entry point.
#
# If +lib+ is found, then the path it was found on is added to the list of
# library paths searched and linked against.
#
def find_library(lib, func, *paths, &b)
  func = "main" if !func or func.empty?
  lib = with_config(lib+'lib', lib)
  paths = paths.collect {|path| path.split(File::PATH_SEPARATOR)}.flatten
  checking_for "#{func}() in #{LIBARG%lib}" do
    libpath = $LIBPATH
    libs = append_library($libs, lib)
    begin
      until r = try_func(func, libs, &b) or paths.empty?
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

# Returns whether or not the function +func+ can be found in the common
# header files, or within any +headers+ that you provide.  If found, a
# macro is passed as a preprocessor constant to the compiler using the
# function name, in uppercase, prepended with 'HAVE_'.
#
# For example, if have_func('foo') returned true, then the HAVE_FOO
# preprocessor macro would be passed to the compiler.
#
def have_func(func, headers = nil, &b)
  checking_for checking_message("#{func}()", headers) do
    if try_func(func, $libs, headers, &b)
      $defs.push(format("-DHAVE_%s", func.tr_cpp))
      true
    else
      false
    end
  end
end

# Returns whether or not the variable +var+ can be found in the common
# header files, or within any +headers+ that you provide.  If found, a
# macro is passed as a preprocessor constant to the compiler using the
# variable name, in uppercase, prepended with 'HAVE_'.
#
# For example, if have_var('foo') returned true, then the HAVE_FOO
# preprocessor macro would be passed to the compiler.
#
def have_var(var, headers = nil, &b)
  checking_for checking_message(var, headers) do
    if try_var(var, headers, &b)
      $defs.push(format("-DHAVE_%s", var.tr_cpp))
      true
    else
      false
    end
  end
end

# Returns whether or not the given +header+ file can be found on your system.
# If found, a macro is passed as a preprocessor constant to the compiler using
# the header file name, in uppercase, prepended with 'HAVE_'.
#
# For example, if have_header('foo.h') returned true, then the HAVE_FOO_H
# preprocessor macro would be passed to the compiler.
#
def have_header(header, preheaders = nil, &b)
  checking_for header do
    if try_header(cpp_include(preheaders)+cpp_include(header), &b)
      $defs.push(format("-DHAVE_%s", header.tr_cpp))
      true
    else
      false
    end
  end
end

# Returns whether or not the given +framework+ can be found on your system.
# If found, a macro is passed as a preprocessor constant to the compiler using
# the framework name, in uppercase, prepended with 'HAVE_FRAMEWORK_'.
#
# For example, if have_framework('Ruby') returned true, then the HAVE_FRAMEWORK_RUBY
# preprocessor macro would be passed to the compiler.
#
def have_framework(fw, &b)
  checking_for fw do
    src = cpp_include("#{fw}/#{fw}.h") << "\n" "int main(void){return 0;}"
    if try_link(src, opt = "-framework #{fw}", &b)
      $defs.push(format("-DHAVE_FRAMEWORK_%s", fw.tr_cpp))
      $LDFLAGS << " " << opt
      true
    else
      false
    end
  end
end

# Instructs mkmf to search for the given +header+ in any of the +paths+
# provided, and returns whether or not it was found in those paths.
#
# If the header is found then the path it was found on is added to the list
# of included directories that are sent to the compiler (via the -I switch).
#
def find_header(header, *paths)
  message = checking_message(header, paths)
  header = cpp_include(header)
  checking_for message do
    if try_header(header)
      true
    else
      found = false
      paths.each do |dir|
        opt = "-I#{dir}".quote
        if try_header(header, opt)
          $INCFLAGS << " " << opt
          found = true
          break
        end
      end
      found
    end
  end
end

# Returns whether or not the struct of type +type+ contains +member+.  If
# it does not, or the struct type can't be found, then false is returned.  You
# may optionally specify additional +headers+ in which to look for the struct
# (in addition to the common header files).
#
# If found, a macro is passed as a preprocessor constant to the compiler using
# the type name and the member name, in uppercase, prepended with 'HAVE_'.
#
# For example, if have_struct_member('struct foo', 'bar') returned true, then the
# HAVE_STRUCT_FOO_BAR preprocessor macro would be passed to the compiler.
#
# HAVE_ST_BAR is also defined for backward compatibility.
#
def have_struct_member(type, member, headers = nil, &b)
  checking_for checking_message("#{type}.#{member}", headers) do
    if try_compile(<<"SRC", &b)
#{cpp_include(headers)}
/*top*/
#{MAIN_DOES_NOTHING}
int s = (char *)&((#{type}*)0)->#{member} - (char *)0;
SRC
      $defs.push(format("-DHAVE_%s_%s", type.tr_cpp, member.tr_cpp))
      $defs.push(format("-DHAVE_ST_%s", member.tr_cpp)) # backward compatibility
      true
    else
      false
    end
  end
end

def try_type(type, headers = nil, opt = "", &b)
  if try_compile(<<"SRC", opt, &b)
#{cpp_include(headers)}
/*top*/
typedef #{type} conftest_type;
int conftestval[sizeof(conftest_type)?1:-1];
SRC
    $defs.push(format("-DHAVE_TYPE_%s", type.tr_cpp))
    true
  else
    false
  end
end

# Returns whether or not the static type +type+ is defined.  You may
# optionally pass additional +headers+ to check against in addition to the
# common header files.
#
# You may also pass additional flags to +opt+ which are then passed along to
# the compiler.
#
# If found, a macro is passed as a preprocessor constant to the compiler using
# the type name, in uppercase, prepended with 'HAVE_TYPE_'.
#
# For example, if have_type('foo') returned true, then the HAVE_TYPE_FOO
# preprocessor macro would be passed to the compiler.
#
def have_type(type, headers = nil, opt = "", &b)
  checking_for checking_message(type, headers, opt) do
    try_type(type, headers, opt, &b)
  end
end

# Returns where the static type +type+ is defined.
#
# You may also pass additional flags to +opt+ which are then passed along to
# the compiler.
#
# See also +have_type+.
#
def find_type(type, opt, *headers, &b)
  opt ||= ""
  fmt = "not found"
  def fmt.%(x)
    x ? x.respond_to?(:join) ? x.join(",") : x : self
  end
  checking_for checking_message(type, nil, opt), fmt do
    headers.find do |h|
      try_type(type, h, opt, &b)
    end
  end
end

def try_const(const, headers = nil, opt = "", &b)
  const, type = *const
  if try_compile(<<"SRC", opt, &b)
#{cpp_include(headers)}
/*top*/
typedef #{type || 'int'} conftest_type;
conftest_type conftestval = #{type ? '' : '(int)'}#{const};
SRC
    $defs.push(format("-DHAVE_CONST_%s", const.tr_cpp))
    true
  else
    false
  end
end

# Returns whether or not the constant +const+ is defined.  You may
# optionally pass the +type+ of +const+ as <code>[const, type]</code>,
# like as:
#
#   have_const(%w[PTHREAD_MUTEX_INITIALIZER pthread_mutex_t], "pthread.h")
#
# You may also pass additional +headers+ to check against in addition
# to the common header files, and additional flags to +opt+ which are
# then passed along to the compiler.
#
# If found, a macro is passed as a preprocessor constant to the compiler using
# the type name, in uppercase, prepended with 'HAVE_CONST_'.
#
# For example, if have_const('foo') returned true, then the HAVE_CONST_FOO
# preprocessor macro would be passed to the compiler.
#
def have_const(const, headers = nil, opt = "", &b)
  checking_for checking_message([*const].compact.join(' '), headers, opt) do
    try_const(const, headers, opt, &b)
  end
end

STRING_OR_FAILED_FORMAT = "%s"
# :stopdoc:
def STRING_OR_FAILED_FORMAT.%(x)
  x ? super : "failed"
end
# :startdoc:

# Returns the size of the given +type+.  You may optionally specify additional
# +headers+ to search in for the +type+.
#
# If found, a macro is passed as a preprocessor constant to the compiler using
# the type name, in uppercase, prepended with 'SIZEOF_', followed by the type
# name, followed by '=X' where 'X' is the actual size.
#
# For example, if check_sizeof('mystruct') returned 12, then the
# SIZEOF_MYSTRUCT=12 preprocessor macro would be passed to the compiler.
#
def check_sizeof(type, headers = nil, opts = "", &b)
  typename, member = type.split('.', 2)
  prelude = cpp_include(headers).split(/$/)
  prelude << "typedef #{typename} rbcv_typedef_;\n"
  prelude << "static rbcv_typedef_ *rbcv_ptr_;\n"
  prelude = [prelude]
  expr = "sizeof((*rbcv_ptr_)#{"." << member if member})"
  fmt = STRING_OR_FAILED_FORMAT
  checking_for checking_message("size of #{type}", headers), fmt do
    if UNIVERSAL_INTS.include?(type)
      type
    elsif size = UNIVERSAL_INTS.find {|t|
        try_static_assert("#{expr} == sizeof(#{t})", prelude, opts, &b)
      }
      $defs.push(format("-DSIZEOF_%s=SIZEOF_%s", type.tr_cpp, size.tr_cpp))
      size
    elsif size = try_constant(expr, prelude, opts, &b)
      $defs.push(format("-DSIZEOF_%s=%s", type.tr_cpp, size))
      size
    end
  end
end

# Returns the signedness of the given +type+.  You may optionally
# specify additional +headers+ to search in for the +type+.
#
# If the +type+ is found and is a numeric type, a macro is passed as a
# preprocessor constant to the compiler using the +type+ name, in
# uppercase, prepended with 'SIGNEDNESS_OF_', followed by the +type+
# name, followed by '=X' where 'X' is positive integer if the +type+ is
# unsigned, or negative integer if the +type+ is signed.
#
# For example, if size_t is defined as unsigned, then
# check_signedness('size_t') would returned +1 and the
# SIGNEDNESS_OF_SIZE_T=+1 preprocessor macro would be passed to the
# compiler, and SIGNEDNESS_OF_INT=-1 if check_signedness('int') is
# done.
#
def check_signedness(type, headers = nil)
  signed = nil
  checking_for("signedness of #{type}", STRING_OR_FAILED_FORMAT) do
    if try_static_assert("(#{type})-1 < 0")
      signed = -1
    elsif try_static_assert("(#{type})-1 > 0")
      signed = +1
    else
      next nil
    end
    $defs.push("-DSIGNEDNESS_OF_%s=%+d" % [type.tr_cpp, signed])
    signed < 0 ? "signed" : "unsigned"
  end
  signed
end

# :stopdoc:

# Used internally by the what_type? method to determine if +type+ is a scalar
# pointer.
def scalar_ptr_type?(type, member = nil, headers = nil, &b)
  try_compile(<<"SRC", &b)   # pointer
#{cpp_include(headers)}
/*top*/
volatile #{type} conftestval;
#{MAIN_DOES_NOTHING}
int t() {return (int)(1-*(conftestval#{member ? ".#{member}" : ""}));}
SRC
end

# Used internally by the what_type? method to determine if +type+ is a scalar
# pointer.
def scalar_type?(type, member = nil, headers = nil, &b)
  try_compile(<<"SRC", &b)   # pointer
#{cpp_include(headers)}
/*top*/
volatile #{type} conftestval;
#{MAIN_DOES_NOTHING}
int t() {return (int)(1-(conftestval#{member ? ".#{member}" : ""}));}
SRC
end

# Used internally by the what_type? method to check if _typeof_ GCC
# extension is available.
def have_typeof?
  return $typeof if defined?($typeof)
  $typeof = %w[__typeof__ typeof].find do |t|
    try_compile(<<SRC)
int rbcv_foo;
#{t}(rbcv_foo) rbcv_bar;
SRC
  end
end

def what_type?(type, member = nil, headers = nil, &b)
  m = "#{type}"
  var = val = "*rbcv_var_"
  func = "rbcv_func_(void)"
  if member
    m << "." << member
  else
    type, member = type.split('.', 2)
  end
  if member
    val = "(#{var}).#{member}"
  end
  prelude = [cpp_include(headers).split(/^/)]
  prelude << ["typedef #{type} rbcv_typedef_;\n",
              "extern rbcv_typedef_ *#{func};\n",
              "static rbcv_typedef_ #{var};\n",
             ]
  type = "rbcv_typedef_"
  fmt = member && !(typeof = have_typeof?) ? "seems %s" : "%s"
  if typeof
    var = "*rbcv_member_"
    func = "rbcv_mem_func_(void)"
    member = nil
    type = "rbcv_mem_typedef_"
    prelude[-1] << "typedef #{typeof}(#{val}) #{type};\n"
    prelude[-1] << "extern #{type} *#{func};\n"
    prelude[-1] << "static #{type} #{var};\n"
    val = var
  end
  def fmt.%(x)
    x ? super : "unknown"
  end
  checking_for checking_message(m, headers), fmt do
    if scalar_ptr_type?(type, member, prelude, &b)
      if try_static_assert("sizeof(*#{var}) == 1", prelude)
        return "string"
      end
      ptr = "*"
    elsif scalar_type?(type, member, prelude, &b)
      unless member and !typeof or try_static_assert("(#{type})-1 < 0", prelude)
        unsigned = "unsigned"
      end
      ptr = ""
    else
      next
    end
    type = UNIVERSAL_INTS.find do |t|
      pre = prelude
      unless member
        pre += [["static #{unsigned} #{t} #{ptr}#{var};\n",
                 "extern #{unsigned} #{t} #{ptr}*#{func};\n"]]
      end
      try_static_assert("sizeof(#{ptr}#{val}) == sizeof(#{unsigned} #{t})", pre)
    end
    type or next
    [unsigned, type, ptr].join(" ").strip
  end
end

# This method is used internally by the find_executable method.
#
# Internal use only.
#
def find_executable0(bin, path = nil)
  exts = config_string('EXECUTABLE_EXTS') {|s| s.split} || config_string('EXEEXT') {|s| [s]}
  if File.expand_path(bin) == bin
    return bin if File.executable?(bin)
    if exts
      exts.each {|ext| File.executable?(file = bin + ext) and return file}
    end
    return nil
  end
  if path ||= ENV['PATH']
    path = path.split(File::PATH_SEPARATOR)
  else
    path = %w[/usr/local/bin /usr/ucb /usr/bin /bin]
  end
  file = nil
  path.each do |dir|
    return file if File.executable?(file = File.join(dir, bin))
    if exts
      exts.each {|ext| File.executable?(ext = file + ext) and return ext}
    end
  end
  nil
end

# :startdoc:

# Searches for the executable +bin+ on +path+. The default path is your
# PATH environment variable. If that isn't defined, it will resort to
# searching /usr/local/bin, /usr/ucb, /usr/bin and /bin.
#
# If found, it will return the full path, including the executable name,
# of where it was found.
#
# Note that this method does not actually affect the generated Makefile.
#
def find_executable(bin, path = nil)
  checking_for checking_message(bin, path) do
    find_executable0(bin, path)
  end
end

# :stopdoc:

def arg_config(config, default=nil, &block)
  $arg_config << [config, default]
  defaults = []
  if default
    defaults << default
  elsif !block
    defaults << nil
  end
  $configure_args.fetch(config.tr('_', '-'), *defaults, &block)
end

# :startdoc:

# Tests for the presence of a --with-<tt>config</tt> or --without-<tt>config</tt>
# option. Returns true if the with option is given, false if the without
# option is given, and the default value otherwise.
#
# This can be useful for adding custom definitions, such as debug information.
#
# Example:
#
#    if with_config("debug")
#       $defs.push("-DOSSL_DEBUG") unless $defs.include? "-DOSSL_DEBUG"
#    end
#
def with_config(config, default=nil)
  config = config.sub(/^--with[-_]/, '')
  val = arg_config("--with-"+config) do
    if arg_config("--without-"+config)
      false
    elsif block_given?
      yield(config, default)
    else
      break default
    end
  end
  case val
  when "yes"
    true
  when "no"
    false
  else
    val
  end
end

# Tests for the presence of an --enable-<tt>config</tt> or
# --disable-<tt>config</tt> option. Returns true if the enable option is given,
# false if the disable option is given, and the default value otherwise.
#
# This can be useful for adding custom definitions, such as debug information.
#
# Example:
#
#    if enable_config("debug")
#       $defs.push("-DOSSL_DEBUG") unless $defs.include? "-DOSSL_DEBUG"
#    end
#
def enable_config(config, default=nil)
  if arg_config("--enable-"+config)
    true
  elsif arg_config("--disable-"+config)
    false
  elsif block_given?
    yield(config, default)
  else
    return default
  end
end

# Generates a header file consisting of the various macro definitions generated
# by other methods such as have_func and have_header. These are then wrapped in
# a custom #ifndef based on the +header+ file name, which defaults to
# 'extconf.h'.
#
# For example:
#
#    # extconf.rb
#    require 'mkmf'
#    have_func('realpath')
#    have_header('sys/utime.h')
#    create_header
#    create_makefile('foo')
#
# The above script would generate the following extconf.h file:
#
#    #ifndef EXTCONF_H
#    #define EXTCONF_H
#    #define HAVE_REALPATH 1
#    #define HAVE_SYS_UTIME_H 1
#    #endif
#
# Given that the create_header method generates a file based on definitions
# set earlier in your extconf.rb file, you will probably want to make this
# one of the last methods you call in your script.
#
def create_header(header = "extconf.h")
  message "creating %s\n", header
  sym = header.tr_cpp
  hdr = ["#ifndef #{sym}\n#define #{sym}\n"]
  for line in $defs
    case line
    when /^-D([^=]+)(?:=(.*))?/
      hdr << "#define #$1 #{$2 ? Shellwords.shellwords($2)[0].gsub(/(?=\t+)/, "\\\n") : 1}\n"
    when /^-U(.*)/
      hdr << "#undef #$1\n"
    end
  end
  hdr << "#endif\n"
  hdr = hdr.join
  unless (IO.read(header) == hdr rescue false)
    open(header, "wb") do |hfile|
      hfile.write(hdr)
    end
  end
  $extconf_h = header
end

# Sets a +target+ name that the user can then use to configure various 'with'
# options with on the command line by using that name.  For example, if the
# target is set to "foo", then the user could use the --with-foo-dir command
# line option.
#
# You may pass along additional 'include' or 'lib' defaults via the +idefault+
# and +ldefault+ parameters, respectively.
#
# Note that dir_config only adds to the list of places to search for libraries
# and include files.  It does not link the libraries into your application.
#
def dir_config(target, idefault=nil, ldefault=nil)
  if dir = with_config(target + "-dir", (idefault unless ldefault))
    defaults = Array === dir ? dir : dir.split(File::PATH_SEPARATOR)
    idefault = ldefault = nil
  end

  idir = with_config(target + "-include", idefault)
  $arg_config.last[1] ||= "${#{target}-dir}/include"
  ldir = with_config(target + "-lib", ldefault)
  $arg_config.last[1] ||= "${#{target}-dir}/lib"

  idirs = idir ? Array === idir ? idir.dup : idir.split(File::PATH_SEPARATOR) : []
  if defaults
    idirs.concat(defaults.collect {|d| d + "/include"})
    idir = ([idir] + idirs).compact.join(File::PATH_SEPARATOR)
  end
  unless idirs.empty?
    idirs.collect! {|d| "-I" + d}
    idirs -= Shellwords.shellwords($CPPFLAGS)
    unless idirs.empty?
      $CPPFLAGS = (idirs.quote << $CPPFLAGS).join(" ")
    end
  end

  ldirs = ldir ? Array === ldir ? ldir.dup : ldir.split(File::PATH_SEPARATOR) : []
  if defaults
    ldirs.concat(defaults.collect {|d| d + "/lib"})
    ldir = ([ldir] + ldirs).compact.join(File::PATH_SEPARATOR)
  end
  $LIBPATH = ldirs | $LIBPATH

  [idir, ldir]
end

# :stopdoc:

# Handles meta information about installed libraries. Uses your platform's
# pkg-config program if it has one.
def pkg_config(pkg)
  if pkgconfig = with_config("#{pkg}-config") and find_executable0(pkgconfig)
    # iff package specific config command is given
    get = proc {|opt| `#{pkgconfig} --#{opt}`.chomp}
  elsif ($PKGCONFIG ||=
         (pkgconfig = with_config("pkg-config", ("pkg-config" unless CROSS_COMPILING))) &&
         find_executable0(pkgconfig) && pkgconfig) and
      system("#{$PKGCONFIG} --exists #{pkg}")
    # default to pkg-config command
    get = proc {|opt| `#{$PKGCONFIG} --#{opt} #{pkg}`.chomp}
  elsif find_executable0(pkgconfig = "#{pkg}-config")
    # default to package specific config command, as a last resort.
    get = proc {|opt| `#{pkgconfig} --#{opt}`.chomp}
  end
  if get
    cflags = get['cflags']
    ldflags = get['libs']
    libs = get['libs-only-l']
    ldflags = (Shellwords.shellwords(ldflags) - Shellwords.shellwords(libs)).quote.join(" ")
    $CFLAGS += " " << cflags
    $LDFLAGS += " " << ldflags
    $libs += " " << libs
    Logging::message "package configuration for %s\n", pkg
    Logging::message "cflags: %s\nldflags: %s\nlibs: %s\n\n",
                     cflags, ldflags, libs
    [cflags, ldflags, libs]
  else
    Logging::message "package configuration for %s is not found\n", pkg
    nil
  end
end

def with_destdir(dir)
  dir = dir.sub($dest_prefix_pattern, '')
  /\A\$[\(\{]/ =~ dir ? dir : "$(DESTDIR)"+dir
end

# Converts forward slashes to backslashes. Aimed at MS Windows.
#
# Internal use only.
#
def winsep(s)
  s.tr('/', '\\')
end

# Converts native path to format acceptable in Makefile
#
# Internal use only.
#
if !CROSS_COMPILING
  case CONFIG['build_os']
  when 'mingw32'
    def mkintpath(path)
      # mingw uses make from msys and it needs special care
      # converts from C:\some\path to /C/some/path
      path = path.dup
      path.tr!('\\', '/')
      path.sub!(/\A([A-Za-z]):(?=\/)/, '/\1')
      path
    end
  end
end
unless defined?(mkintpath)
  def mkintpath(path)
    path
  end
end

def configuration(srcdir)
  mk = []
  vpath = $VPATH.dup
  if !CROSS_COMPILING
    case CONFIG['build_os']
    when 'cygwin'
      if CONFIG['target_os'] != 'cygwin'
        vpath = vpath.map {|p| p.sub(/.*/, '$(shell cygpath -u \&)')}
      end
    end
  end
  CONFIG["hdrdir"] ||= $hdrdir
  mk << %{
SHELL = /bin/sh

#### Start of system configuration section. ####
#{"top_srcdir = " + $top_srcdir.sub(%r"\A#{Regexp.quote($topdir)}/", "$(topdir)/") if $extmk}
srcdir = #{srcdir.gsub(/\$\((srcdir)\)|\$\{(srcdir)\}/) {mkintpath(CONFIG[$1||$2])}.quote}
topdir = #{mkintpath($extmk ? CONFIG["topdir"] : $topdir).quote}
hdrdir = #{mkintpath(CONFIG["hdrdir"]).quote}
arch_hdrdir = #{$arch_hdrdir}
VPATH = #{vpath.join(CONFIG['PATH_SEPARATOR'])}
}
  if $extmk
    mk << "RUBYLIB =\n""RUBYOPT = -\n"
  end
  if destdir = CONFIG["prefix"][$dest_prefix_pattern, 1]
    mk << "\nDESTDIR = #{destdir}\n"
  end
  CONFIG.each do |key, var|
    next unless /prefix$/ =~ key
    mk << "#{key} = #{with_destdir(var)}\n"
  end
  CONFIG.each do |key, var|
    next if /^abs_/ =~ key
    next if /^(?:src|top|hdr)dir$/ =~ key
    next unless /dir$/ =~ key
    mk << "#{key} = #{with_destdir(var)}\n"
  end
  if !$extmk and !$configure_args.has_key?('--ruby') and
      sep = config_string('BUILD_FILE_SEPARATOR')
    sep = ":/=#{sep}"
  else
    sep = ""
  end
  possible_command = (proc {|s| s if /top_srcdir/ !~ s} unless $extmk)
  extconf_h = $extconf_h ? "-DRUBY_EXTCONF_H=\\\"$(RUBY_EXTCONF_H)\\\" " : $defs.join(" ") << " "
  mk << %{
CC = #{CONFIG['CC']}
CXX = #{CONFIG['CXX']}
LIBRUBY = #{CONFIG['LIBRUBY']}
LIBRUBY_A = #{CONFIG['LIBRUBY_A']}
LIBRUBYARG_SHARED = #$LIBRUBYARG_SHARED
LIBRUBYARG_STATIC = #$LIBRUBYARG_STATIC
OUTFLAG = #{OUTFLAG}
COUTFLAG = #{COUTFLAG}

RUBY_EXTCONF_H = #{$extconf_h}
cflags   = #{CONFIG['cflags']}
optflags = #{CONFIG['optflags']}
debugflags = #{CONFIG['debugflags']}
warnflags = #{CONFIG['warnflags']}
CFLAGS   = #{$static ? '' : CONFIG['CCDLFLAGS']} #$CFLAGS #$ARCH_FLAG
INCFLAGS = -I. #$INCFLAGS
DEFS     = #{CONFIG['DEFS']}
CPPFLAGS = #{extconf_h}#{$CPPFLAGS}
CXXFLAGS = $(CFLAGS) #{CONFIG['CXXFLAGS']}
ldflags  = #{$LDFLAGS}
dldflags = #{$DLDFLAGS}
ARCH_FLAG = #{$ARCH_FLAG}
DLDFLAGS = $(ldflags) $(dldflags)
LDSHARED = #{CONFIG['LDSHARED']}
LDSHAREDXX = #{config_string('LDSHAREDXX') || '$(LDSHARED)'}
AR = #{CONFIG['AR']}
EXEEXT = #{CONFIG['EXEEXT']}

RUBY_BASE_NAME = #{CONFIG['RUBY_BASE_NAME']}
RUBY_INSTALL_NAME = #{CONFIG['RUBY_INSTALL_NAME']}
RUBY_SO_NAME = #{CONFIG['RUBY_SO_NAME']}
arch = #{CONFIG['arch']}
sitearch = #{CONFIG['sitearch']}
ruby_version = #{RbConfig::CONFIG['ruby_version']}
ruby = #{$ruby}
RUBY = $(ruby#{sep})
RM = #{config_string('RM', &possible_command) || '$(RUBY) -run -e rm -- -f'}
RM_RF = #{'$(RUBY) -run -e rm -- -rf'}
RMDIRS = #{config_string('RMDIRS', &possible_command) || '$(RUBY) -run -e rmdir -- -p'}
MAKEDIRS = #{config_string('MAKEDIRS', &possible_command) || '@$(RUBY) -run -e mkdir -- -p'}
INSTALL = #{config_string('INSTALL', &possible_command) || '@$(RUBY) -run -e install -- -vp'}
INSTALL_PROG = #{config_string('INSTALL_PROG') || '$(INSTALL) -m 0755'}
INSTALL_DATA = #{config_string('INSTALL_DATA') || '$(INSTALL) -m 0644'}
COPY = #{config_string('CP', &possible_command) || '@$(RUBY) -run -e cp -- -v'}

#### End of system configuration section. ####

preload = #{defined?($preload) && $preload ? $preload.join(' ') : ''}
}
  if $nmake == ?b
    mk.each do |x|
      x.gsub!(/^(MAKEDIRS|INSTALL_(?:PROG|DATA))+\s*=.*\n/) do
        "!ifndef " + $1 + "\n" +
        $& +
	"!endif\n"
      end
    end
  end
  mk
end
# :startdoc:

def dummy_makefile(srcdir)
  configuration(srcdir) << <<RULES << CLEANINGS
CLEANFILES = #{$cleanfiles.join(' ')}
DISTCLEANFILES = #{$distcleanfiles.join(' ')}

all install static install-so install-rb: Makefile
.PHONY: all install static install-so install-rb
.PHONY: clean clean-so clean-rb

RULES
end

def depend_rules(depend)
  suffixes = []
  depout = []
  cont = implicit = nil
  impconv = proc do
    COMPILE_RULES.each {|rule| depout << (rule % implicit[0]) << implicit[1]}
    implicit = nil
  end
  ruleconv = proc do |line|
    if implicit
      if /\A\t/ =~ line
        implicit[1] << line
        next
      else
        impconv[]
      end
    end
    if m = /\A\.(\w+)\.(\w+)(?:\s*:)/.match(line)
      suffixes << m[1] << m[2]
      implicit = [[m[1], m[2]], [m.post_match]]
      next
    elsif RULE_SUBST and /\A(?!\s*\w+\s*=)[$\w][^#]*:/ =~ line
      line.gsub!(%r"(\s)(?!\.)([^$(){}+=:\s\/\\,]+)(?=\s|\z)") {$1 + RULE_SUBST % $2}
    end
    depout << line
  end
  depend.each_line do |line|
    line.gsub!(/\.o\b/, ".#{$OBJEXT}")
    line.gsub!(/\$\((?:hdr|top)dir\)\/config.h/, $config_h)
    line.gsub!(%r"\$\(hdrdir\)/(?!ruby(?![^:;/\s]))(?=[-\w]+\.h)", '\&ruby/')
    if $nmake && /\A\s*\$\(RM|COPY\)/ =~ line
      line.gsub!(%r"[-\w\./]{2,}"){$&.tr("/", "\\")}
      line.gsub!(/(\$\((?!RM|COPY)[^:)]+)(?=\))/, '\1:/=\\')
    end
    if /(?:^|[^\\])(?:\\\\)*\\$/ =~ line
      (cont ||= []) << line
      next
    elsif cont
      line = (cont << line).join
      cont = nil
    end
    ruleconv.call(line)
  end
  if cont
    ruleconv.call(cont.join)
  elsif implicit
    impconv.call
  end
  unless suffixes.empty?
    depout.unshift(".SUFFIXES: ." + suffixes.uniq.join(" .") + "\n\n")
  end
  depout.unshift("$(OBJS): $(RUBY_EXTCONF_H)\n\n") if $extconf_h
  depout.flatten!
  depout
end

# Generates the Makefile for your extension, passing along any options and
# preprocessor constants that you may have generated through other methods.
#
# The +target+ name should correspond the name of the global function name
# defined within your C extension, minus the 'Init_'.  For example, if your
# C extension is defined as 'Init_foo', then your target would simply be 'foo'.
#
# If any '/' characters are present in the target name, only the last name
# is interpreted as the target name, and the rest are considered toplevel
# directory names, and the generated Makefile will be altered accordingly to
# follow that directory structure.
#
# For example, if you pass 'test/foo' as a target name, your extension will
# be installed under the 'test' directory.  This means that in order to
# load the file within a Ruby program later, that directory structure will
# have to be followed, e.g. "require 'test/foo'".
#
# The +srcprefix+ should be used when your source files are not in the same
# directory as your build script. This will not only eliminate the need for
# you to manually copy the source files into the same directory as your build
# script, but it also sets the proper +target_prefix+ in the generated
# Makefile.
#
# Setting the +target_prefix+ will, in turn, install the generated binary in
# a directory under your RbConfig::CONFIG['sitearchdir'] that mimics your local
# filesystem when you run 'make install'.
#
# For example, given the following file tree:
#
#    ext/
#       extconf.rb
#       test/
#          foo.c
#
# And given the following code:
#
#    create_makefile('test/foo', 'test')
#
# That will set the +target_prefix+ in the generated Makefile to 'test'. That,
# in turn, will create the following file tree when installed via the
# 'make install' command:
#
#    /path/to/ruby/sitearchdir/test/foo.so
#
# It is recommended that you use this approach to generate your makefiles,
# instead of copying files around manually, because some third party
# libraries may depend on the +target_prefix+ being set properly.
#
# The +srcprefix+ argument can be used to override the default source
# directory, i.e. the current directory . It is included as part of the VPATH
# and added to the list of INCFLAGS.
#
def create_makefile(target, srcprefix = nil)
  $target = target
  libpath = $DEFLIBPATH|$LIBPATH
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

  srcprefix ||= "$(srcdir)/#{srcprefix}".chomp('/')
  RbConfig.expand(srcdir = srcprefix.dup)

  ext = ".#{$OBJEXT}"
  if not $objs
    srcs = $srcs || Dir[File.join(srcdir, "*.{#{SRC_EXT.join(%q{,})}}")]
    objs = srcs.inject(Hash.new {[]}) {|h, f| h[File.basename(f, ".*") << ext] <<= f; h}
    $objs = objs.keys
    unless objs.delete_if {|b, f| f.size == 1}.empty?
      dups = objs.sort.map {|b, f|
        "#{b[/.*\./]}{#{f.collect {|n| n[/([^.]+)\z/]}.join(',')}}"
      }
      abort "source files duplication - #{dups.join(", ")}"
    end
  else
    $objs.collect! {|o| File.basename(o, ".*") << ext} unless $OBJEXT == "o"
    srcs = $srcs || $objs.collect {|o| o.chomp(ext) << ".c"}
  end
  $srcs = srcs

  target = nil if $objs.empty?

  if target and EXPORT_PREFIX
    if File.exist?(File.join(srcdir, target + '.def'))
      deffile = "$(srcdir)/$(TARGET).def"
      unless EXPORT_PREFIX.empty?
        makedef = %{-pe "$_.sub!(/^(?=\\w)/,'#{EXPORT_PREFIX}') unless 1../^EXPORTS$/i"}
      end
    else
      makedef = %{-e "puts 'EXPORTS', '#{EXPORT_PREFIX}Init_$(TARGET)'"}
    end
    if makedef
      $cleanfiles << '$(DEFFILE)'
      origdef = deffile
      deffile = "$(TARGET)-$(arch).def"
    end
  end
  origdef ||= ''

  if $extout and $INSTALLFILES
    $cleanfiles.concat($INSTALLFILES.collect {|files, dir|File.join(dir, files.sub(/\A\.\//, ''))})
    $distcleandirs.concat($INSTALLFILES.collect {|files, dir| dir})
  end

  if $extmk and not $extconf_h
    create_header
  end

  libpath = libpathflag(libpath)

  dllib = target ? "$(TARGET).#{CONFIG['DLEXT']}" : ""
  staticlib = target ? "$(TARGET).#$LIBEXT" : ""
  mfile = open("Makefile", "wb")
  conf = configuration(srcprefix)
  conf = yield(conf) if block_given?
  mfile.puts(conf)
  mfile.print "
libpath = #{($DEFLIBPATH|$LIBPATH).join(" ")}
LIBPATH = #{libpath}
DEFFILE = #{deffile}

CLEANFILES = #{$cleanfiles.join(' ')}
DISTCLEANFILES = #{$distcleanfiles.join(' ')}
DISTCLEANDIRS = #{$distcleandirs.join(' ')}

extout = #{$extout && $extout.quote}
extout_prefix = #{$extout_prefix}
target_prefix = #{target_prefix}
LOCAL_LIBS = #{$LOCAL_LIBS}
LIBS = #{$LIBRUBYARG} #{$libs} #{$LIBS}
SRCS = #{srcs.collect(&File.method(:basename)).join(' ')}
OBJS = #{$objs.join(" ")}
TARGET = #{target}
DLLIB = #{dllib}
EXTSTATIC = #{$static || ""}
STATIC_LIB = #{staticlib unless $static.nil?}
#{!$extout && defined?($installed_list) ? "INSTALLED_LIST = #{$installed_list}\n" : ""}
" #"
  # TODO: fixme
  install_dirs.each {|d| mfile.print("%-14s= %s\n" % d) if /^[[:upper:]]/ =~ d[0]}
  n = ($extout ? '$(RUBYARCHDIR)/' : '') + '$(TARGET)'
  mfile.print "
TARGET_SO     = #{($extout ? '$(RUBYARCHDIR)/' : '')}$(DLLIB)
CLEANLIBS     = #{n}.#{CONFIG['DLEXT']} #{config_string('cleanlibs') {|t| t.gsub(/\$\*/) {n}}}
CLEANOBJS     = *.#{$OBJEXT} #{config_string('cleanobjs') {|t| t.gsub(/\$\*/, "$(TARGET)#{deffile ? '-$(arch)': ''}")} if target} *.bak

all:    #{$extout ? "install" : target ? "$(DLLIB)" : "Makefile"}
static: $(STATIC_LIB)#{$extout ? " install-rb" : ""}
.PHONY: all install static install-so install-rb
.PHONY: clean clean-so clean-rb
"
  mfile.print CLEANINGS
  fsep = config_string('BUILD_FILE_SEPARATOR') {|s| s unless s == "/"}
  if fsep
    sep = ":/=#{fsep}"
    fseprepl = proc {|s|
      s = s.gsub("/", fsep)
      s = s.gsub(/(\$\(\w+)(\))/) {$1+sep+$2}
      s = s.gsub(/(\$\{\w+)(\})/) {$1+sep+$2}
    }
  else
    fseprepl = proc {|s| s}
    sep = ""
  end
  dirs = []
  mfile.print "install: install-so install-rb\n\n"
  sodir = (dir = "$(RUBYARCHDIR)").dup
  mfile.print("install-so: ")
  if target
    f = "$(DLLIB)"
    dest = "#{dir}/#{f}"
    mfile.puts dir, "install-so: #{dest}"
    if $extout
      mfile.print "clean-so::\n"
      mfile.print "\t@-$(RM) #{fseprepl[dest]}\n"
      mfile.print "\t@-$(RMDIRS) #{fseprepl[dir]}#{$ignore_error}\n"
    else
      mfile.print "#{dest}: #{f}\n\t@-$(MAKEDIRS) $(@D#{sep})\n"
      mfile.print "\t$(INSTALL_PROG) #{fseprepl[f]} $(@D#{sep})\n"
      if defined?($installed_list)
	mfile.print "\t@echo #{dir}/#{File.basename(f)}>>$(INSTALLED_LIST)\n"
      end
    end
  else
    mfile.puts "Makefile"
  end
  mfile.print("install-rb: pre-install-rb install-rb-default\n")
  mfile.print("install-rb-default: pre-install-rb-default\n")
  mfile.print("pre-install-rb: Makefile\n")
  mfile.print("pre-install-rb-default: Makefile\n")
  for sfx, i in [["-default", [["lib/**/*.rb", "$(RUBYLIBDIR)", "lib"]]], ["", $INSTALLFILES]]
    files = install_files(mfile, i, nil, srcprefix) or next
    for dir, *files in files
      unless dirs.include?(dir)
	dirs << dir
	mfile.print "pre-install-rb#{sfx}: #{dir}\n"
      end
      for f in files
	dest = "#{dir}/#{File.basename(f)}"
	mfile.print("install-rb#{sfx}: #{dest} #{dir}\n")
	mfile.print("#{dest}: #{f}\n")
	mfile.print("\t$(#{$extout ? 'COPY' : 'INSTALL_DATA'}) #{f} $(@D#{sep})\n")
	if defined?($installed_list) and !$extout
	  mfile.print("\t@echo #{dest}>>$(INSTALLED_LIST)\n")
	end
        if $extout
          mfile.print("clean-rb#{sfx}::\n")
          mfile.print("\t@-$(RM) #{fseprepl[dest]}\n")
        end
      end
    end
    if $extout
      dirs.uniq!
      unless dirs.empty?
        mfile.print("clean-rb#{sfx}::\n")
        for dir in dirs.sort_by {|d| -d.count('/')}
          mfile.print("\t@-$(RMDIRS) #{fseprepl[dir]}#{$ignore_error}\n")
        end
      end
    end
  end
  dirs.unshift(sodir) if target and !dirs.include?(sodir)
  dirs.each {|d| mfile.print "#{d}:\n\t$(MAKEDIRS) $@\n"}

  mfile.print <<-SITEINSTALL

site-install: site-install-so site-install-rb
site-install-so: install-so
site-install-rb: install-rb

  SITEINSTALL

  return unless target

  mfile.puts SRC_EXT.collect {|e| ".path.#{e} = $(VPATH)"} if $nmake == ?b
  mfile.print ".SUFFIXES: .#{SRC_EXT.join(' .')} .#{$OBJEXT}\n"
  mfile.print "\n"

  CXX_EXT.each do |e|
    COMPILE_RULES.each do |rule|
      mfile.printf(rule, e, $OBJEXT)
      mfile.printf("\n\t%s\n\n", COMPILE_CXX)
    end
  end
  %w[c].each do |e|
    COMPILE_RULES.each do |rule|
      mfile.printf(rule, e, $OBJEXT)
      mfile.printf("\n\t%s\n\n", COMPILE_C)
    end
  end
  %w[m].each do |e|
    COMPILE_RULES.each do |rule|
      mfile.printf(rule, e, $OBJEXT)
      mfile.printf("\n\t%s\n\n", COMPILE_OBJC)
    end
  end

  mfile.print "$(RUBYARCHDIR)/" if $extout
  mfile.print "$(DLLIB): "
  mfile.print "$(DEFFILE) " if makedef
  mfile.print "$(OBJS) Makefile\n"
  mfile.print "\t@-$(RM) $(@#{sep})\n"
  mfile.print "\t@-$(MAKEDIRS) $(@D)\n" if $extout
  link_so = LINK_SO.gsub(/^/, "\t")
  if srcs.any?(&%r"\.(?:#{CXX_EXT.join('|')})\z".method(:===))
    link_so = link_so.sub(/\bLDSHARED\b/, '\&XX')
  end
  mfile.print link_so, "\n\n"
  unless $static.nil?
    mfile.print "$(STATIC_LIB): $(OBJS)\n\t@-$(RM) $(@#{sep})\n\t"
    mfile.print "$(AR) #{config_string('ARFLAGS') || 'cru '}$@ $(OBJS)"
    config_string('RANLIB') do |ranlib|
      mfile.print "\n\t@-#{ranlib} $(DLLIB) 2> /dev/null || true"
    end
  end
  mfile.print "\n\n"
  if makedef
    mfile.print "$(DEFFILE): #{origdef}\n"
    mfile.print "\t$(RUBY) #{makedef} #{origdef} > $@\n\n"
  end

  depend = File.join(srcdir, "depend")
  if File.exist?(depend)
    mfile.print("###\n", *depend_rules(File.read(depend)))
  else
    headers = %w[$(hdrdir)/ruby.h $(hdrdir)/ruby/defines.h]
    if RULE_SUBST
      headers.each {|h| h.sub!(/.*/, &RULE_SUBST.method(:%))}
    end
    headers << $config_h
    headers << '$(RUBY_EXTCONF_H)' if $extconf_h
    mfile.print "$(OBJS): ", headers.join(' '), "\n"
  end

  $makefile_created = true
ensure
  mfile.close if mfile
end

# :stopdoc:

def init_mkmf(config = CONFIG)
  $makefile_created = false
  $arg_config = []
  $enable_shared = config['ENABLE_SHARED'] == 'yes'
  $defs = []
  $extconf_h = nil
  $CFLAGS = with_config("cflags", arg_config("CFLAGS", config["CFLAGS"])).dup
  $ARCH_FLAG = with_config("arch_flag", arg_config("ARCH_FLAG", config["ARCH_FLAG"])).dup
  $CPPFLAGS = with_config("cppflags", arg_config("CPPFLAGS", config["CPPFLAGS"])).dup
  $LDFLAGS = with_config("ldflags", arg_config("LDFLAGS", config["LDFLAGS"])).dup
  $INCFLAGS = "-I$(arch_hdrdir)"
  $INCFLAGS << " -I$(hdrdir)/ruby/backward" unless $extmk
  $INCFLAGS << " -I$(hdrdir) -I$(srcdir)"
  $DLDFLAGS = with_config("dldflags", arg_config("DLDFLAGS", config["DLDFLAGS"])).dup
  $LIBEXT = config['LIBEXT'].dup
  $OBJEXT = config["OBJEXT"].dup
  $LIBS = "#{config['LIBS']} #{config['DLDLIBS']}"
  $LIBRUBYARG = ""
  $LIBRUBYARG_STATIC = config['LIBRUBYARG_STATIC']
  $LIBRUBYARG_SHARED = config['LIBRUBYARG_SHARED']
  $DEFLIBPATH = [$extmk ? "$(topdir)" : "$(libdir)"]
  $DEFLIBPATH.unshift(".")
  $LIBPATH = []
  $INSTALLFILES = []
  $NONINSTALLFILES = [/~\z/, /\A#.*#\z/, /\A\.#/, /\.bak\z/i, /\.orig\z/, /\.rej\z/, /\.l[ao]\z/, /\.o\z/]
  $VPATH = %w[$(srcdir) $(arch_hdrdir)/ruby $(hdrdir)/ruby]

  $objs = nil
  $srcs = nil
  $libs = ""
  if $enable_shared or RbConfig.expand(config["LIBRUBY"].dup) != RbConfig.expand(config["LIBRUBY_A"].dup)
    $LIBRUBYARG = config['LIBRUBYARG']
  end

  $LOCAL_LIBS = ""

  $cleanfiles = config_string('CLEANFILES') {|s| Shellwords.shellwords(s)} || []
  $cleanfiles << "mkmf.log"
  $distcleanfiles = config_string('DISTCLEANFILES') {|s| Shellwords.shellwords(s)} || []
  $distcleandirs = config_string('DISTCLEANDIRS') {|s| Shellwords.shellwords(s)} || []

  $extout ||= nil
  $extout_prefix ||= nil

  $arg_config.clear
  dir_config("opt")
end

FailedMessage = <<MESSAGE
Could not create Makefile due to some reason, probably lack of
necessary libraries and/or headers.  Check the mkmf.log file for more
details.  You may need configuration options.

Provided configuration options:
MESSAGE

# Returns whether or not the Makefile was successfully generated. If not,
# the script will abort with an error message.
#
# Internal use only.
#
def mkmf_failed(path)
  unless $makefile_created or File.exist?("Makefile")
    opts = $arg_config.collect {|t, n| "\t#{t}#{n ? "=#{n}" : ""}\n"}
    abort "*** #{path} failed ***\n" + FailedMessage + opts.join
  end
end

# :startdoc:

init_mkmf

$make = with_config("make-prog", ENV["MAKE"] || "make")
make, = Shellwords.shellwords($make)
$nmake = nil
case
when $mswin
  $nmake = ?m if /nmake/i =~ make
when $bccwin
  $nmake = ?b if /Borland/i =~ `#{make} -h`
end
$ignore_error = $nmake ? '' : ' 2> /dev/null || true'

RbConfig::CONFIG["srcdir"] = CONFIG["srcdir"] =
  $srcdir = arg_config("--srcdir", File.dirname($0))
$configure_args["--topsrcdir"] ||= $srcdir
if $curdir = arg_config("--curdir")
  RbConfig.expand(curdir = $curdir.dup)
else
  curdir = $curdir = "."
end
unless File.expand_path(RbConfig::CONFIG["topdir"]) == File.expand_path(curdir)
  CONFIG["topdir"] = $curdir
  RbConfig::CONFIG["topdir"] = curdir
end
$configure_args["--topdir"] ||= $curdir
$ruby = arg_config("--ruby", File.join(RbConfig::CONFIG["bindir"], CONFIG["ruby_install_name"]))

split = Shellwords.method(:shellwords).to_proc

EXPORT_PREFIX = config_string('EXPORT_PREFIX') {|s| s.strip}

hdr = ['#include "ruby.h"' "\n"]
config_string('COMMON_MACROS') do |s|
  Shellwords.shellwords(s).each do |w|
    hdr << "#define " + w.split(/=/, 2).join(" ")
  end
end
config_string('COMMON_HEADERS') do |s|
  Shellwords.shellwords(s).each {|w| hdr << "#include <#{w}>"}
end
COMMON_HEADERS = hdr.join("\n")
COMMON_LIBS = config_string('COMMON_LIBS', &split) || []

COMPILE_RULES = config_string('COMPILE_RULES', &split) || %w[.%s.%s:]
RULE_SUBST = config_string('RULE_SUBST')
COMPILE_C = config_string('COMPILE_C') || '$(CC) $(INCFLAGS) $(CPPFLAGS) $(CFLAGS) $(COUTFLAG)$@ -c $<'
COMPILE_CXX = config_string('COMPILE_CXX') || '$(CXX) $(INCFLAGS) $(CPPFLAGS) $(CXXFLAGS) $(COUTFLAG)$@ -c $<'
COMPILE_OBJC = config_string('COMPILE_OBJC') || COMPILE_C
TRY_LINK = config_string('TRY_LINK') ||
  "$(CC) #{OUTFLAG}conftest $(INCFLAGS) $(CPPFLAGS) " \
  "$(CFLAGS) $(src) $(LIBPATH) $(LDFLAGS) $(ARCH_FLAG) $(LOCAL_LIBS) $(LIBS)"
LINK_SO = config_string('LINK_SO') ||
  if CONFIG["DLEXT"] == $OBJEXT
    "ld $(DLDFLAGS) -r -o $@ $(OBJS)\n"
  else
    "$(LDSHARED) #{OUTFLAG}$@ $(OBJS) " \
    "$(LIBPATH) $(DLDFLAGS) $(LOCAL_LIBS) $(LIBS)"
  end
LIBPATHFLAG = config_string('LIBPATHFLAG') || ' -L"%s"'
RPATHFLAG = config_string('RPATHFLAG') || ''
LIBARG = config_string('LIBARG') || '-l%s'
MAIN_DOES_NOTHING = config_string('MAIN_DOES_NOTHING') || 'int main() {return 0;}'
UNIVERSAL_INTS = config_string('UNIVERSAL_INTS') {|s| Shellwords.shellwords(s)} ||
  %w[int short long long\ long]

sep = config_string('BUILD_FILE_SEPARATOR') {|s| ":/=#{s}" if s != "/"} || ""
CLEANINGS = "
clean-rb-default::
clean-rb::
clean-so::
clean: clean-so clean-rb-default clean-rb
\t\t@-$(RM) $(CLEANLIBS#{sep}) $(CLEANOBJS#{sep}) $(CLEANFILES#{sep})

distclean-rb-default::
distclean-rb::
distclean-so::
distclean: clean distclean-so distclean-rb-default distclean-rb
\t\t@-$(RM) Makefile $(RUBY_EXTCONF_H) conftest.* mkmf.log
\t\t@-$(RM) core ruby$(EXEEXT) *~ $(DISTCLEANFILES#{sep})
\t\t@-$(RMDIRS) $(DISTCLEANDIRS#{sep})#{$ignore_error}

realclean: distclean
"

if not $extmk and /\A(extconf|makefile).rb\z/ =~ File.basename($0)
  END {mkmf_failed($0)}
end
