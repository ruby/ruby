# module to create Makefile for extension modules
# invoke like: ruby -r mkmf extconf.rb

require 'rbconfig'
require 'fileutils'
require 'shellwords'

CONFIG = Config::MAKEFILE_CONFIG
ORIG_LIBPATH = ENV['LIB']

CXX_EXT = %w[cc cxx cpp]
if /mswin|bccwin|mingw|msdosdjgpp|human|os2/ !~ CONFIG['build_os']
  CXX_EXT.concat(%w[C])
end
SRC_EXT = %w[c m] << CXX_EXT
$static = $config_h = nil
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
$human = /human/ =~ RUBY_PLATFORM
$netbsd = /netbsd/ =~ RUBY_PLATFORM
$os2 = /os2/ =~ RUBY_PLATFORM
$beos = /beos/ =~ RUBY_PLATFORM
$solaris = /solaris/ =~ RUBY_PLATFORM
$dest_prefix_pattern = (File::PATH_SEPARATOR == ';' ? /\A([[:alpha:]]:)?/ : /\A/)

# :stopdoc:

def config_string(key, config = CONFIG)
  s = config[key] and !s.empty? and block_given? ? yield(s) : s
end

def dir_re(dir)
  Regexp.new('\$(?:\('+dir+'\)|\{'+dir+'\})(?:\$(?:\(target_prefix\)|\{target_prefix\}))?')
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
  [dir_re('bindir'), "$(BINDIR)"],
  [dir_re('vendorarchdir'), "$(RUBYARCHDIR)"],
]

def install_dirs(target_prefix = nil)
  if $extout
    dirs = [
      ['BINDIR',        '$(extout)/bin'],
      ['RUBYCOMMONDIR', '$(extout)/common'],
      ['RUBYLIBDIR',    '$(RUBYCOMMONDIR)$(target_prefix)'],
      ['RUBYARCHDIR',   '$(extout)/$(arch)$(target_prefix)'],
      ['extout',        "#$extout"],
      ['extout_prefix', "#$extout_prefix"],
    ]
  elsif $extmk
    dirs = [
      ['BINDIR',        '$(bindir)'],
      ['RUBYCOMMONDIR', '$(rubylibdir)'],
      ['RUBYLIBDIR',    '$(rubylibdir)$(target_prefix)'],
      ['RUBYARCHDIR',   '$(archdir)$(target_prefix)'],
    ]
  elsif $configure_args.has_key?('--vendor')
    dirs = [
      ['BINDIR',        '$(bindir)'],
      ['RUBYCOMMONDIR', '$(vendordir)$(target_prefix)'],
      ['RUBYLIBDIR',    '$(vendorlibdir)$(target_prefix)'],
      ['RUBYARCHDIR',   '$(vendorarchdir)$(target_prefix)'],
    ]
  else
    dirs = [
      ['BINDIR',        '$(bindir)'],
      ['RUBYCOMMONDIR', '$(sitedir)$(target_prefix)'],
      ['RUBYLIBDIR',    '$(sitelibdir)$(target_prefix)'],
      ['RUBYARCHDIR',   '$(sitearchdir)$(target_prefix)'],
    ]
  end
  dirs << ['target_prefix', (target_prefix ? "/#{target_prefix}" : "")]
  dirs
end

def map_dir(dir, map = nil)
  map ||= INSTALL_DIRS
  map.inject(dir) {|dir, (orig, new)| dir.gsub(orig, new)}
end

topdir = File.dirname(libdir = File.dirname(__FILE__))
extdir = File.expand_path("ext", topdir)
$extmk = File.expand_path($0)[0, extdir.size+1] == extdir+"/"
if not $extmk and File.exist?(($hdrdir = Config::CONFIG["archdir"]) + "/ruby.h")
  $topdir = $hdrdir
elsif File.exist?(($hdrdir = ($top_srcdir ||= topdir))  + "/ruby.h") and
    File.exist?(($topdir ||= Config::CONFIG["topdir"]) + "/config.h")
else
  abort "mkmf.rb can't find header files for ruby at #{$hdrdir}/ruby.h"
end

OUTFLAG = CONFIG['OUTFLAG']
CPPOUTFILE = CONFIG['CPPOUTFILE']

CONFTEST_C = "conftest.c"

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
  FileUtils.rm_f(Dir[files.join("\0")])
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

  def self::open
    @log ||= File::open(@logfile, 'w')
    @log.sync = true
    $stderr.reopen(@log)
    $stdout.reopen(@log)
    yield
  ensure
    $stderr.reopen(@orgerr)
    $stdout.reopen(@orgout)
  end

  def self::message(*s)
    @log ||= File::open(@logfile, 'w')
    @log.sync = true
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
        @log.close
        File::open(tmplog) {|t| FileUtils.copy_stream(t, log)}
      ensure
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
  src = yield(src) if block_given?
  src = src.gsub(/[ \t]+$/, '').gsub(/\A\n+|^\n+$/, '').sub(/[^\n]\z/, "\\&\n")
  open(CONFTEST_C, "wb") do |cfile|
    cfile.print src
  end
  src
end

def try_do(src, command, &b)
  src = create_tmpsrc(src, &b)
  xsystem(command)
ensure
  log_src(src)
end

def link_command(ldflags, opt="", libpath=$DEFLIBPATH|$LIBPATH)
  conf = Config::CONFIG.merge('hdrdir' => $hdrdir.quote,
                              'src' => CONFTEST_C,
                              'INCFLAGS' => $INCFLAGS,
                              'CPPFLAGS' => $CPPFLAGS,
                              'CFLAGS' => "#$CFLAGS",
                              'ARCH_FLAG' => "#$ARCH_FLAG",
                              'LDFLAGS' => "#$LDFLAGS #{ldflags}",
                              'LIBPATH' => libpathflag(libpath),
                              'LOCAL_LIBS' => "#$LOCAL_LIBS #$libs",
                              'LIBS' => "#$LIBRUBYARG_STATIC #{opt} #$LIBS")
  Config::expand(TRY_LINK.dup, conf)
end

def cc_command(opt="")
  conf = Config::CONFIG.merge('hdrdir' => $hdrdir.quote, 'srcdir' => $srcdir.quote)
  Config::expand("$(CC) #$INCFLAGS #$CPPFLAGS #$CFLAGS #$ARCH_FLAG #{opt} -c #{CONFTEST_C}",
		 conf)
end

def cpp_command(outfile, opt="")
  conf = Config::CONFIG.merge('hdrdir' => $hdrdir.quote, 'srcdir' => $srcdir.quote)
  Config::expand("$(CPP) #$INCFLAGS #$CPPFLAGS #$CFLAGS #{opt} #{CONFTEST_C} #{outfile}",
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
  try_do(src, link_command("", opt), &b)
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

def cpp_include(header)
  if header
    header = [header] unless header.kind_of? Array
    header.map {|h| "#include <#{h}>\n"}.join
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
#{COMMON_HEADERS}
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
    src = %{#{COMMON_HEADERS}
#{includes}
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
  try_link(<<"SRC", libs, &b) or try_link(<<"SRC", libs, &b)
#{COMMON_HEADERS}
#{headers}
/*top*/
int main() { return 0; }
int t() { void ((*volatile p)()); p = (void ((*)()))#{func}; return 0; }
SRC
#{headers}
/*top*/
int main() { return 0; }
int t() { #{func}(); return 0; }
SRC
end

def try_var(var, headers = nil, &b)
  headers = cpp_include(headers)
  try_compile(<<"SRC", &b)
#{COMMON_HEADERS}
#{headers}
/*top*/
int main() { return 0; }
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
  srcprefix ||= '$(srcdir)'
  Config::expand(srcdir = srcprefix.dup)
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
    Dir.glob(files) do |f|
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
  f = caller[0][/in `(.*)'$/, 1] and f << ": " #` for vim
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
def have_header(header, &b)
  checking_for header do
    if try_cpp(cpp_include(header), &b)
      $defs.push(format("-DHAVE_%s", header.tr("a-z./\055", "A-Z___")))
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
    if try_cpp(header)
      true
    else
      found = false
      paths.each do |dir|
        opt = "-I#{dir}".quote
        if try_cpp(header, opt)
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
# the member name, in uppercase, prepended with 'HAVE_ST_'.
#
# For example, if have_struct_member('struct foo', 'bar') returned true, then the
# HAVE_ST_BAR preprocessor macro would be passed to the compiler.
# 
def have_struct_member(type, member, headers = nil, &b)
  checking_for checking_message("#{type}.#{member}", headers) do
    if try_compile(<<"SRC", &b)
#{COMMON_HEADERS}
#{cpp_include(headers)}
/*top*/
int main() { return 0; }
int s = (char *)&((#{type}*)0)->#{member} - (char *)0;
SRC
      $defs.push(format("-DHAVE_ST_%s", member.tr_cpp))
      true
    else
      false
    end
  end
end

def try_type(type, headers = nil, opt = "", &b)
  if try_compile(<<"SRC", opt, &b)
#{COMMON_HEADERS}
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
#{COMMON_HEADERS}
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
def check_sizeof(type, headers = nil, &b)
  expr = "sizeof(#{type})"
  fmt = "%d"
  def fmt.%(x)
    x ? super : "failed"
  end
  checking_for checking_message("size of #{type}", headers), fmt do
    if size = try_constant(expr, headers, &b)
      $defs.push(format("-DSIZEOF_%s=%d", type.tr_cpp, size))
      size
    end
  end
end

# :stopdoc:

# Used internally by the what_type? method to determine if +type+ is a scalar
# pointer.
def scalar_ptr_type?(type, member = nil, headers = nil, &b)
  try_compile(<<"SRC", &b)   # pointer
#{COMMON_HEADERS}
#{cpp_include(headers)}
/*top*/
volatile #{type} conftestval;
int main() { return 0; }
int t() {return (int)(1-*(conftestval#{member ? ".#{member}" : ""}));}
SRC
end

# Used internally by the what_type? method to determine if +type+ is a scalar
# pointer.
def scalar_type?(type, member = nil, headers = nil, &b)
  try_compile(<<"SRC", &b)   # pointer
#{COMMON_HEADERS}
#{cpp_include(headers)}
/*top*/
volatile #{type} conftestval;
int main() { return 0; }
int t() {return (int)(1-(conftestval#{member ? ".#{member}" : ""}));}
SRC
end

def what_type?(type, member = nil, headers = nil, &b)
  m = "#{type}"
  name = type
  if member
    m << "." << member
    name = "(((#{type} *)0)->#{member})"
  end
  fmt = "seems %s"
  def fmt.%(x)
    x ? super : "unknown"
  end
  checking_for checking_message(m, headers), fmt do
    if scalar_ptr_type?(type, member, headers, &b)
      if try_static_assert("sizeof(*#{name}) == 1", headers)
        "string"
      end
    elsif scalar_type?(type, member, headers, &b)
      if try_static_assert("sizeof(#{name}) > sizeof(long)", headers)
        "long long"
      elsif try_static_assert("sizeof(#{name}) > sizeof(int)", headers)
        "long"
      elsif try_static_assert("sizeof(#{name}) > sizeof(short)", headers)
        "int"
      elsif try_static_assert("sizeof(#{name}) > 1", headers)
        "short"
      else
        "char"
      end
    end
  end
end

# This method is used internally by the find_executable method.
#
# Internal use only.
#
def find_executable0(bin, path = nil)
  ext = config_string('EXEEXT')
  if File.expand_path(bin) == bin
    return bin if File.executable?(bin)
    ext and File.executable?(file = bin + ext) and return file
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
    return file if ext and File.executable?(file << ext)
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

def arg_config(config, *defaults, &block)
  $arg_config << [config, *defaults]
  defaults << nil if !block and defaults.empty?
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
def with_config(config, *defaults)
  config = config.sub(/^--with[-_]/, '')
  val = arg_config("--with-"+config) do
    if arg_config("--without-"+config)
      false
    elsif block_given?
      yield(config, *defaults)
    else
      break *defaults
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
def enable_config(config, *defaults)
  if arg_config("--enable-"+config)
    true
  elsif arg_config("--disable-"+config)
    false
  elsif block_given?
    yield(config, *defaults)
  else
    return *defaults
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
  sym = header.tr("a-z./\055", "A-Z___")
  hdr = ["#ifndef #{sym}\n#define #{sym}\n"]
  for line in $defs
    case line
    when /^-D([^=]+)(?:=(.*))?/
      hdr << "#define #$1 #{$2 ? Shellwords.shellwords($2)[0] : 1}\n"
    when /^-U(.*)/
      hdr << "#undef #$1\n"
    end
  end
  hdr << "#endif\n"
  hdr = hdr.join
  unless (IO.read(header) == hdr rescue false)
    open(header, "w") do |hfile|
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

  idirs = idir ? Array === idir ? idir : idir.split(File::PATH_SEPARATOR) : []
  if defaults
    idirs.concat(defaults.collect {|dir| dir + "/include"})
    idir = ([idir] + idirs).compact.join(File::PATH_SEPARATOR)
  end
  unless idirs.empty?
    idirs.collect! {|dir| "-I" + dir}
    idirs -= Shellwords.shellwords($CPPFLAGS)
    unless idirs.empty?
      $CPPFLAGS = (idirs.quote << $CPPFLAGS).join(" ")
    end
  end

  ldirs = ldir ? Array === ldir ? ldir : ldir.split(File::PATH_SEPARATOR) : []
  if defaults
    ldirs.concat(defaults.collect {|dir| dir + "/lib"})
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

def configuration(srcdir)
  mk = []
  vpath = %w[$(srcdir) $(topdir) $(hdrdir)]
  if !CROSS_COMPILING
    case CONFIG['build_os']
    when 'cygwin'
      if CONFIG['target_os'] != 'cygwin'
        vpath.each {|p| p.sub!(/.*/, '$(shell cygpath -u \&)')}
      end
    when 'msdosdjgpp', 'mingw32'
      CONFIG['PATH_SEPARATOR'] = ';'
    end
  end
  mk << %{
SHELL = /bin/sh

#### Start of system configuration section. ####
#{
if $extmk
  "top_srcdir = " + $top_srcdir.sub(%r"\A#{Regexp.quote($topdir)}/", "$(topdir)/")
end
}
srcdir = #{srcdir.gsub(/\$\((srcdir)\)|\$\{(srcdir)\}/) {CONFIG[$1||$2]}.quote}
topdir = #{($extmk ? CONFIG["topdir"] : $topdir).quote}
hdrdir = #{$extmk ? CONFIG["hdrdir"].quote : '$(topdir)'}
VPATH = #{vpath.join(CONFIG['PATH_SEPARATOR'])}
}
  if $extmk
    mk << "RUBYLIB = -\nRUBYOPT = -rpurelib.rb\n"
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
    next unless /^(?:src|top|hdr|(.*))dir$/ =~ key and $1
    mk << "#{key} = #{with_destdir(var)}\n"
  end
  if !$extmk and !$configure_args.has_key?('--ruby') and
      sep = config_string('BUILD_FILE_SEPARATOR')
    sep = ":/=#{sep}"
  else
    sep = ""
  end
  extconf_h = $extconf_h ? "-DRUBY_EXTCONF_H=\\\"$(RUBY_EXTCONF_H)\\\" " : $defs.join(" ")<<" "
  mk << %{
CC = #{CONFIG['CC']}
LIBRUBY = #{CONFIG['LIBRUBY']}
LIBRUBY_A = #{CONFIG['LIBRUBY_A']}
LIBRUBYARG_SHARED = #$LIBRUBYARG_SHARED
LIBRUBYARG_STATIC = #$LIBRUBYARG_STATIC

RUBY_EXTCONF_H = #{$extconf_h}
CFLAGS   = #{$static ? '' : CONFIG['CCDLFLAGS']} #$CFLAGS #$ARCH_FLAG
INCFLAGS = -I. #$INCFLAGS
DEFS     = #{CONFIG['DEFS']}
CPPFLAGS = #{extconf_h}#{$CPPFLAGS}
CXXFLAGS = $(CFLAGS) #{CONFIG['CXXFLAGS']}
ldflags  = #{$LDFLAGS}
dldflags = #{$DLDFLAGS}
archflag = #{$ARCH_FLAG}
DLDFLAGS = $(ldflags) $(dldflags) $(archflag)
LDSHARED = #{CONFIG['LDSHARED']}
AR = #{CONFIG['AR']}
EXEEXT = #{CONFIG['EXEEXT']}

RUBY_INSTALL_NAME = #{CONFIG['RUBY_INSTALL_NAME']}
RUBY_SO_NAME = #{CONFIG['RUBY_SO_NAME']}
arch = #{CONFIG['arch']}
sitearch = #{CONFIG['sitearch']}
ruby_version = #{Config::CONFIG['ruby_version']}
ruby = #{$ruby}
RUBY = $(ruby#{sep})
RM = #{config_string('RM') || '$(RUBY) -run -e rm -- -f'}
MAKEDIRS = #{config_string('MAKEDIRS') || '@$(RUBY) -run -e mkdir -- -p'}
INSTALL = #{config_string('INSTALL') || '@$(RUBY) -run -e install -- -vp'}
INSTALL_PROG = #{config_string('INSTALL_PROG') || '$(INSTALL) -m 0755'}
INSTALL_DATA = #{config_string('INSTALL_DATA') || '$(INSTALL) -m 0644'}
COPY = #{config_string('CP') || '@$(RUBY) -run -e cp -- -v'}

#### End of system configuration section. ####

preload = #{$preload ? $preload.join(' ') : ''}
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

def dummy_makefile(srcdir)
  configuration(srcdir) << <<RULES << CLEANINGS
CLEANFILES = #{$cleanfiles.join(' ')}
DISTCLEANFILES = #{$distcleanfiles.join(' ')}

all install static install-so install-rb: Makefile

RULES
end
# :startdoc:

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
# a directory under your Config::CONFIG['sitearchdir'] that mimics your local
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

  srcprefix ||= '$(srcdir)'
  Config::expand(srcdir = srcprefix.dup)

  if not $objs
    $objs = []
    srcs = Dir[File.join(srcdir, "*.{#{SRC_EXT.join(%q{,})}}")]
    for f in srcs
      obj = File.basename(f, ".*") << ".o"
      $objs.push(obj) unless $objs.index(obj)
    end
  elsif !(srcs = $srcs)
    srcs = $objs.collect {|obj| obj.sub(/\.o\z/, '.c')}
  end
  $srcs = srcs
  for i in $objs
    i.sub!(/\.o\z/, ".#{$OBJEXT}")
  end
  $objs = $objs.join(" ")

  target = nil if $objs == ""

  if target and EXPORT_PREFIX
    if File.exist?(File.join(srcdir, target + '.def'))
      deffile = "$(srcdir)/$(TARGET).def"
      unless EXPORT_PREFIX.empty?
        makedef = %{-pe "sub!(/^(?=\\w)/,'#{EXPORT_PREFIX}') unless 1../^EXPORTS$/i"}
      end
    else
      makedef = %{-e "puts 'EXPORTS', '#{EXPORT_PREFIX}Init_$(TARGET)'"}
    end
    if makedef
      $distcleanfiles << '$(DEFFILE)'
      origdef = deffile
      deffile = "$(TARGET)-$(arch).def"
    end
  end
  origdef ||= ''

  libpath = libpathflag(libpath)

  dllib = target ? "$(TARGET).#{CONFIG['DLEXT']}" : ""
  staticlib = target ? "$(TARGET).#$LIBEXT" : ""
  mfile = open("Makefile", "wb")
  mfile.print configuration(srcprefix)
  mfile.print "
libpath = #{($DEFLIBPATH|$LIBPATH).join(" ")}
LIBPATH = #{libpath}
DEFFILE = #{deffile}

CLEANFILES = #{$cleanfiles.join(' ')}
DISTCLEANFILES = #{$distcleanfiles.join(' ')}

extout = #{$extout}
extout_prefix = #{$extout_prefix}
target_prefix = #{target_prefix}
LOCAL_LIBS = #{$LOCAL_LIBS}
LIBS = #{$LIBRUBYARG} #{$libs} #{$LIBS}
SRCS = #{srcs.collect(&File.method(:basename)).join(' ')}
OBJS = #{$objs}
TARGET = #{target}
DLLIB = #{dllib}
EXTSTATIC = #{$static || ""}
STATIC_LIB = #{staticlib unless $static.nil?}
#{!$extout && defined?($installed_list) ? "INSTALLED_LIST = #{$installed_list}\n" : ""}
"
  install_dirs.each {|d| mfile.print("%-14s= %s\n" % d) if /^[[:upper:]]/ =~ d[0]}
  n = ($extout ? '$(RUBYARCHDIR)/' : '') + '$(TARGET).'
  mfile.print "
TARGET_SO     = #{($extout ? '$(RUBYARCHDIR)/' : '')}$(DLLIB)
CLEANLIBS     = #{n}#{CONFIG['DLEXT']} #{n}il? #{n}tds #{n}map
CLEANOBJS     = *.#{$OBJEXT} *.#{$LIBEXT} *.s[ol] *.pdb *.exp *.bak

all:		#{$extout ? "install" : target ? "$(DLLIB)" : "Makefile"}
static:		$(STATIC_LIB)#{$extout ? " install-rb" : ""}
"
  mfile.print CLEANINGS
  dirs = []
  mfile.print "install: install-so install-rb\n\n"
  sodir = (dir = "$(RUBYARCHDIR)").dup
  mfile.print("install-so: ")
  if target
    f = "$(DLLIB)"
    dest = "#{dir}/#{f}"
    mfile.puts dir, "install-so: #{dest}"
    unless $extout
      mfile.print "#{dest}: #{f}\n"
      if (sep = config_string('BUILD_FILE_SEPARATOR'))
        f.gsub!("/", sep)
        dir.gsub!("/", sep)
        sep = ":/="+sep
        f.gsub!(/(\$\(\w+)(\))/) {$1+sep+$2}
        f.gsub!(/(\$\{\w+)(\})/) {$1+sep+$2}
        dir.gsub!(/(\$\(\w+)(\))/) {$1+sep+$2}
        dir.gsub!(/(\$\{\w+)(\})/) {$1+sep+$2}
      end
      mfile.print "\t$(INSTALL_PROG) #{f} #{dir}\n"
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
      files.each do |f|
	dest = "#{dir}/#{File.basename(f)}"
	mfile.print("install-rb#{sfx}: #{dest}\n")
	mfile.print("#{dest}: #{f} #{dir}\n\t$(#{$extout ? 'COPY' : 'INSTALL_DATA'}) ")
	sep = config_string('BUILD_FILE_SEPARATOR')
	if sep
	  f = f.gsub("/", sep)
	  sep = ":/="+sep
	  f = f.gsub(/(\$\(\w+)(\))/) {$1+sep+$2}
	  f = f.gsub(/(\$\{\w+)(\})/) {$1+sep+$2}
	else
	  sep = ""
	end
	mfile.print("#{f} $(@D#{sep})\n")
	if defined?($installed_list) and !$extout
	  mfile.print("\t@echo #{dest}>>$(INSTALLED_LIST)\n")
	end
      end
    end
  end
  dirs.unshift(sodir) if target and !dirs.include?(sodir)
  dirs.each {|dir| mfile.print "#{dir}:\n\t$(MAKEDIRS) $@\n"}

  mfile.print <<-SITEINSTALL

site-install: site-install-so site-install-rb
site-install-so: install-so
site-install-rb: install-rb

  SITEINSTALL

  return unless target

  mfile.puts SRC_EXT.collect {|ext| ".path.#{ext} = $(VPATH)"} if $nmake == ?b
  mfile.print ".SUFFIXES: .#{SRC_EXT.join(' .')} .#{$OBJEXT}\n"
  mfile.print "\n"

  CXX_EXT.each do |ext|
    COMPILE_RULES.each do |rule|
      mfile.printf(rule, ext, $OBJEXT)
      mfile.printf("\n\t%s\n\n", COMPILE_CXX)
    end
  end
  %w[c].each do |ext|
    COMPILE_RULES.each do |rule|
      mfile.printf(rule, ext, $OBJEXT)
      mfile.printf("\n\t%s\n\n", COMPILE_C)
    end
  end

  mfile.print "$(RUBYARCHDIR)/" if $extout
  mfile.print "$(DLLIB): ", (makedef ? "$(DEFFILE) " : ""), "$(OBJS)\n"
  mfile.print "\t@-$(RM) $@\n"
  mfile.print "\t@-$(MAKEDIRS) $(@D)\n" if $extout
  link_so = LINK_SO.gsub(/^/, "\t")
  mfile.print link_so, "\n\n"
  unless $static.nil?
    mfile.print "$(STATIC_LIB): $(OBJS)\n\t"
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
    suffixes = []
    depout = []
    open(depend, "r") do |dfile|
      mfile.printf "###\n"
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
      while line = dfile.gets()
	line.gsub!(/\.o\b/, ".#{$OBJEXT}")
	line.gsub!(/\$\((?:hdr|top)dir\)\/config.h/, $config_h) if $config_h
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
    end
    unless suffixes.empty?
      mfile.print ".SUFFIXES: .", suffixes.uniq.join(" ."), "\n\n"
    end
    mfile.print "$(OBJS): $(RUBY_EXTCONF_H)\n\n" if $extconf_h
    mfile.print depout
  else
    headers = %w[ruby.h defines.h]
    if RULE_SUBST
      headers.each {|h| h.sub!(/.*/) {|*m| RULE_SUBST % m}}
    end
    headers << $config_h if $config_h
    headers << "$(RUBY_EXTCONF_H)" if $extconf_h
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
  $INCFLAGS = "-I$(topdir) -I$(hdrdir) -I$(srcdir)"
  $DLDFLAGS = with_config("dldflags", arg_config("DLDFLAGS", config["DLDFLAGS"])).dup
  $LIBEXT = config['LIBEXT'].dup
  $OBJEXT = config["OBJEXT"].dup
  $LIBS = "#{config['LIBS']} #{config['DLDLIBS']}"
  $LIBRUBYARG = ""
  $LIBRUBYARG_STATIC = config['LIBRUBYARG_STATIC']
  $LIBRUBYARG_SHARED = config['LIBRUBYARG_SHARED']
  $DEFLIBPATH = $extmk ? ["$(topdir)"] : CROSS_COMPILING ? [] : ["$(libdir)"]
  $DEFLIBPATH.unshift(".")
  $LIBPATH = []
  $INSTALLFILES = []
  $NONINSTALLFILES = [/~\z/, /\A#.*#\z/, /\A\.#/, /\.bak\z/i, /\.orig\z/, /\.rej\z/, /\.l[ao]\z/, /\.o\z/]

  $objs = nil
  $srcs = nil
  $libs = ""
  if $enable_shared or Config.expand(config["LIBRUBY"].dup) != Config.expand(config["LIBRUBY_A"].dup)
    $LIBRUBYARG = config['LIBRUBYARG']
  end

  $LOCAL_LIBS = ""

  $cleanfiles = config_string('CLEANFILES') {|s| Shellwords.shellwords(s)} || []
  $cleanfiles << "mkmf.log"
  $distcleanfiles = config_string('DISTCLEANFILES') {|s| Shellwords.shellwords(s)} || []

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

Config::CONFIG["srcdir"] = CONFIG["srcdir"] =
  $srcdir = arg_config("--srcdir", File.dirname($0))
$configure_args["--topsrcdir"] ||= $srcdir
if $curdir = arg_config("--curdir")
  Config.expand(curdir = $curdir.dup)
else
  curdir = $curdir = "."
end
unless File.expand_path(Config::CONFIG["topdir"]) == File.expand_path(curdir)
  CONFIG["topdir"] = $curdir
  Config::CONFIG["topdir"] = curdir
end
$configure_args["--topdir"] ||= $curdir
$ruby = arg_config("--ruby", File.join(Config::CONFIG["bindir"], CONFIG["ruby_install_name"]))

split = Shellwords.method(:shellwords).to_proc

EXPORT_PREFIX = config_string('EXPORT_PREFIX') {|s| s.strip}

hdr = []
config_string('COMMON_MACROS') do |s|
  Shellwords.shellwords(s).each do |w|
    hdr << "#define " + w.split(/=/, 2).join(" ")
  end
end
config_string('COMMON_HEADERS') do |s|
  Shellwords.shellwords(s).each {|s| hdr << "#include <#{s}>"}
end
COMMON_HEADERS = hdr.join("\n")
COMMON_LIBS = config_string('COMMON_LIBS', &split) || []

COMPILE_RULES = config_string('COMPILE_RULES', &split) || %w[.%s.%s:]
RULE_SUBST = config_string('RULE_SUBST')
COMPILE_C = config_string('COMPILE_C') || '$(CC) $(INCFLAGS) $(CPPFLAGS) $(CFLAGS) -c $<'
COMPILE_CXX = config_string('COMPILE_CXX') || '$(CXX) $(INCFLAGS) $(CPPFLAGS) $(CXXFLAGS) -c $<'
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

sep = config_string('BUILD_FILE_SEPARATOR') {|sep| ":/=#{sep}" if sep != "/"} || ""
CLEANINGS = "
clean:
		@-$(RM) $(CLEANLIBS#{sep}) $(CLEANOBJS#{sep}) $(CLEANFILES#{sep})

distclean:	clean
		@-$(RM) Makefile $(RUBY_EXTCONF_H) conftest.* mkmf.log
		@-$(RM) core ruby$(EXEEXT) *~ $(DISTCLEANFILES#{sep})

realclean:	distclean
"

if not $extmk and /\A(extconf|makefile).rb\z/ =~ File.basename($0)
  END {mkmf_failed($0)}
end
