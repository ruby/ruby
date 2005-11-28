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

$mswin = /mswin/ =~ RUBY_PLATFORM
$bccwin = /bccwin/ =~ RUBY_PLATFORM
$mingw = /mingw/ =~ RUBY_PLATFORM
$cygwin = /cygwin/ =~ RUBY_PLATFORM
$human = /human/ =~ RUBY_PLATFORM
$netbsd = /netbsd/ =~ RUBY_PLATFORM
$os2 = /os2/ =~ RUBY_PLATFORM
$beos = /beos/ =~ RUBY_PLATFORM
$solaris = /solaris/ =~ RUBY_PLATFORM

def config_string(key, config = CONFIG)
  s = config[key] and !s.empty? and block_given? ? yield(s) : s
end

def dir_re(dir)
  Regexp.new('\$(?:\('+dir+'\)|\{'+dir+'\})(?:\$\(target_prefix\)|\{target_prefix\})?')
end

INSTALL_DIRS = [
  [dir_re('commondir'), "$(RUBYCOMMONDIR)"],
  [dir_re("sitedir"), "$(RUBYCOMMONDIR)"],
  [dir_re('rubylibdir'), "$(RUBYLIBDIR)"],
  [dir_re('archdir'), "$(RUBYARCHDIR)"],
  [dir_re('sitelibdir'), "$(RUBYLIBDIR)"],
  [dir_re('sitearchdir'), "$(RUBYARCHDIR)"]
]

def install_dirs(target_prefix = nil)
  if $extout
    dirs = [
      ['RUBYCOMMONDIR', '$(extout)'],
      ['RUBYLIBDIR',    '$(extout)$(target_prefix)'],
      ['RUBYARCHDIR',   '$(extout)/$(arch)$(target_prefix)'],
      ['extout',        "#$extout"],
      ['extout_prefix', "#$extout_prefix"],
    ]
  elsif $extmk
    dirs = [
      ['RUBYCOMMONDIR', '$(rubylibdir)'],
      ['RUBYLIBDIR',    '$(rubylibdir)$(target_prefix)'],
      ['RUBYARCHDIR',   '$(archdir)$(target_prefix)'],
    ]
  else
    dirs = [
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
if not $extmk and File.exist?(Config::CONFIG["archdir"] + "/ruby.h")
  $hdrdir = $topdir = Config::CONFIG["archdir"]
elsif File.exist?(($top_srcdir ||= topdir)  + "/ruby.h") and
    File.exist?(($topdir ||= Config::CONFIG["topdir"]) + "/config.h")
  $hdrdir = $top_srcdir
else
  abort "can't find header files for ruby."
end

OUTFLAG = CONFIG['OUTFLAG']
CPPOUTFILE = CONFIG['CPPOUTFILE']

CONFTEST_C = "conftest.c"

class String
  def quote
    /\s/ =~ self ? "\"#{self}\"" : self
  end
end
class Array
  def quote
    map {|s| s.quote}
  end
end

def rm_f(*files)
  FileUtils.rm_f(Dir[files.join("\0")])
end

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

module Logging
  @log = nil
  @logfile = 'mkmf.log'
  @orgerr = $stderr.dup
  @orgout = $stdout.dup
  @postpone = 0

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
end

def xsystem command
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
  Logging::message <<"EOM", src
checked program was:
/* begin */
%s/* end */

EOM
end

def create_tmpsrc(src)
  src = yield(src) if block_given?
  src = src.sub(/[^\n]\z/, "\\&\n")
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

def link_command(ldflags, opt="", libpath=$LIBPATH)
  Config::expand(TRY_LINK.dup,
                 CONFIG.merge('hdrdir' => $hdrdir.quote,
                              'src' => CONFTEST_C,
                              'INCFLAGS' => $INCFLAGS,
                              'CPPFLAGS' => $CPPFLAGS,
                              'CFLAGS' => "#$CFLAGS",
                              'ARCH_FLAG' => "#$ARCH_FLAG",
                              'LDFLAGS' => "#$LDFLAGS #{ldflags}",
                              'LIBPATH' => libpathflag(libpath),
                              'LOCAL_LIBS' => "#$LOCAL_LIBS #$libs",
                              'LIBS' => "#$LIBRUBYARG_STATIC #{opt} #$LIBS"))
end

def cc_command(opt="")
  Config::expand("$(CC) -c #$INCFLAGS -I$(hdrdir) " \
                 "#$CPPFLAGS #$CFLAGS #$ARCH_FLAG #{opt} #{CONFTEST_C}",
		 CONFIG.merge('hdrdir' => $hdrdir.quote))
end

def cpp_command(outfile, opt="")
  Config::expand("$(CPP) #$INCFLAGS -I$(hdrdir) " \
                 "#$CPPFLAGS #$CFLAGS #{opt} #{CONFTEST_C} #{outfile}",
		 CONFIG.merge('hdrdir' => $hdrdir.quote))
end

def libpathflag(libpath=$LIBPATH)
  libpath.map{|x|
    (x == "$(topdir)" ? LIBPATHFLAG : LIBPATHFLAG+RPATHFLAG) % x.quote
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
    unless upper == lower
      if try_static_assert("#{const} == #{lower}", headers, opt)
        upper = lower
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
#{headers}
/*top*/
int main() { return 0; }
int t() { #{func}(); return 0; }
SRC
#{COMMON_HEADERS}
#{headers}
/*top*/
int main() { return 0; }
int t() { void ((*volatile p)()); p = (void ((*)()))#{func}; return 0; }
SRC
end

def try_var(var, headers = nil, &b)
  headers = cpp_include(headers)
  try_compile(<<"SRC", &b)
#{COMMON_HEADERS}
#{headers}
/*top*/
int main() { return 0; }
int t() { void *volatile p; p = (void *)&#{var}; return 0; }
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
  srcprefix ||= '$(srcdir)'
  Config::expand(srcdir = srcprefix.dup)
  dirs = []
  path = Hash.new {|h, i| h[i] = dirs.push([i])[-1]}
  ifiles.each do |files, dir, prefix|
    dir = map_dir(dir, map)
    prefix = %r|\A#{Regexp.quote(prefix)}/?| if prefix
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

def append_library(libs, lib)
  format(LIBARG, lib) + " " + libs
end

def message(*s)
  unless $extmk and not $VERBOSE
    printf(*s)
    $stdout.flush
  end
end

def checking_for(m, fmt = nil)
  f = caller[0][/in `(.*)'$/, 1] and f << ": " #` for vim
  m = "checking for #{m}... "
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

def have_macro(macro, headers = nil, opt = "", &b)
  m = "#{macro}"
  m << " in #{headers.inspect}" if headers
  checking_for m do
    macro_defined?(macro, cpp_include(headers), opt, &b)
  end
end

def have_library(lib, func = nil, header=nil, &b)
  func = "main" if !func or func.empty?
  lib = with_config(lib+'lib', lib)
  checking_for "#{func}() in #{LIBARG%lib}" do
    if COMMON_LIBS.include?(lib)
      true
    else
      libs = append_library($libs, lib)
      if try_func(func, libs, header, &b)
        $libs = libs
        true
      else
        false
      end
    end
  end
end

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

def have_func(func, headers = nil, &b)
  checking_for "#{func}()" do
    if try_func(func, $libs, headers, &b)
      $defs.push(format("-DHAVE_%s", func.upcase))
      true
    else
      false
    end
  end
end

def have_var(var, headers = nil, &b)
  checking_for "#{var}" do
    if try_var(var, headers, &b)
      $defs.push(format("-DHAVE_%s", var.upcase))
      true
    else
      false
    end
  end
end

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

def find_header(header, *paths)
  checking_for header do
    if try_cpp(cpp_include(header))
      true
    else
      found = false
      paths.each do |dir|
        opt = "-I#{dir}".quote
        if try_cpp(cpp_include(header), opt)
          $INCFLAGS << " " << opt
          found = true
          break
        end
      end
      found
    end
  end
end

def have_struct_member(type, member, header = nil, &b)
  checking_for "#{type}.#{member}" do
    if try_compile(<<"SRC", &b)
#{COMMON_HEADERS}
#{cpp_include(header)}
/*top*/
int main() { return 0; }
int s = (char *)&((#{type}*)0)->#{member} - (char *)0;
SRC
      $defs.push(format("-DHAVE_ST_%s", member.upcase))
      true
    else
      false
    end
  end
end

def have_type(type, header = nil, opt = "", &b)
  checking_for type do
    header = cpp_include(header)
    if try_compile(<<"SRC", opt, &b) or (/\A\w+\z/n =~ type && try_compile(<<"SRC", opt, &b))
#{COMMON_HEADERS}
#{header}
/*top*/
static #{type} t;
SRC
#{COMMON_HEADERS}
#{header}
/*top*/
static #{type} *t;
SRC
      $defs.push(format("-DHAVE_TYPE_%s", type.strip.upcase.tr_s("^A-Z0-9_", "_")))
      true
    else
      false
    end
  end
end

def check_sizeof(type, header = nil, &b)
  expr = "sizeof(#{type})"
  m = "checking size of #{type}... "
  message "%s", m
  a = size = nil
  Logging::postpone do
    if size = try_constant(expr, header, &b)
      $defs.push(format("-DSIZEOF_%s=%d", type.upcase.tr_s("^A-Z0-9_", "_"), size))
      a = "#{size}\n"
    else
      a = "failed\n"
    end
    "check_sizeof: #{m}-------------------- #{a}\n"
  end
  message(a)
  Logging::message "--------------------\n\n"
  size
end

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
  m << " in #{headers.inspect}" if headers
  fmt = "seems %s"
  def fmt.%(x)
    x ? super : "unknown"
  end
  checking_for m, fmt do
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

def find_executable0(bin, path = nil)
  ext = config_string('EXEEXT')
  if File.expand_path(bin) == bin
    return bin if File.executable?(bin)
    return file if ext and File.executable?(file = bin + ext)
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

def find_executable(bin, path = nil)
  checking_for bin do
    find_executable0(bin, path)
  end
end

def arg_config(config, *defaults, &block)
  $arg_config << [config, *defaults]
  defaults << nil if !block and defaults.empty?
  $configure_args.fetch(config.tr('_', '-'), *defaults, &block)
end

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

def create_header(header = "extconf.h")
  message "creating %s\n", header
  if $defs.length > 0
    sym = header.tr("a-z./\055", "A-Z___")
    open(header, "w") do |hfile|
      hfile.print "#ifndef #{sym}\n#define #{sym}\n"
      for line in $defs
	case line
	when /^-D([^=]+)(?:=(.*))?/
	  hfile.print "#define #$1 #{$2 || 1}\n"
	when /^-U(.*)/
	  hfile.print "#undef #$1\n"
	end
      end
      hfile.print "#endif\n"
    end
  end
end

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

def pkg_config(pkg)
  unless defined?($PKGCONFIG)
    if pkgconfig = with_config("pkg-config", !CROSS_COMPILING && "pkg-config")
      find_executable0(pkgconfig) or pkgconfig = nil
    end
    $PKGCONFIG = pkgconfig
  end
  if $PKGCONFIG and system("#{$PKGCONFIG} --exists #{pkg}")
    cflags = `#{$PKGCONFIG} --cflags #{pkg}`.chomp
    ldflags = `#{$PKGCONFIG} --libs #{pkg}`.chomp
    libs = `#{$PKGCONFIG} --libs-only-l #{pkg}`.chomp
    ldflags = (Shellwords.shellwords(ldflags) - Shellwords.shellwords(libs)).quote.join(" ")
    $CFLAGS += " " << cflags
    $LDFLAGS += " " << ldflags
    $libs += " " << libs
    Logging::message "package configuration for %s\n", pkg
    Logging::message "cflags: %s\nldflags: %s\nlibs: %s\n\n",
                     cflags, ldflags, libs
    [cflags, ldflags, libs]
  end
end

def with_destdir(dir)
  /^\$[\(\{]/ =~ dir ? dir : "$(DESTDIR)"+dir
end

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

srcdir = #{srcdir.gsub(/\$\((srcdir)\)|\$\{(srcdir)\}/) {CONFIG[$1||$2]}.quote}
topdir = #{($extmk ? CONFIG["topdir"] : $topdir).quote}
hdrdir = #{$extmk ? CONFIG["hdrdir"].quote : '$(topdir)'}
VPATH = #{vpath.join(CONFIG['PATH_SEPARATOR'])}
}
  drive = File::PATH_SEPARATOR == ';' ? /\A\w:/ : /\A/
  if destdir = CONFIG["prefix"].scan(drive)[0] and !destdir.empty?
    mk << "\nDESTDIR = #{destdir}\n"
  end
  CONFIG.each do |key, var|
    next unless /prefix$/ =~ key
    mk << "#{key} = #{with_destdir(var.sub(drive, ''))}\n"
  end
  CONFIG.each do |key, var|
    next if /^abs_/ =~ key
    next unless /^(?:src|top|hdr|(.*))dir$/ =~ key and $1
    mk << "#{key} = #{with_destdir(var.sub(drive, ''))}\n"
  end
  if !$extmk and !$configure_args.has_key?('--ruby') and
      sep = config_string('BUILD_FILE_SEPARATOR')
    sep = ":/=#{sep}"
  else
    sep = ""
  end
  mk << %{
CC = #{CONFIG['CC']}
LIBRUBY = #{CONFIG['LIBRUBY']}
LIBRUBY_A = #{CONFIG['LIBRUBY_A']}
LIBRUBYARG_SHARED = #$LIBRUBYARG_SHARED
LIBRUBYARG_STATIC = #$LIBRUBYARG_STATIC

CFLAGS   = #{CONFIG['CCDLFLAGS'] unless $static} #$CFLAGS #$ARCH_FLAG
CPPFLAGS = -I. -I$(topdir) -I$(hdrdir) -I$(srcdir) #{$defs.join(" ")} #{$CPPFLAGS}
CXXFLAGS = $(CFLAGS) #{CONFIG['CXXFLAGS']}
DLDFLAGS = #$LDFLAGS #$DLDFLAGS #$ARCH_FLAG
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

preload = #{$preload.join(" ") if $preload}
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

def create_makefile(target, srcprefix = nil)
  $target = target
  libpath = $LIBPATH
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

  libpath = libpathflag(libpath)

  dllib = target ? "$(TARGET).#{CONFIG['DLEXT']}" : ""
  staticlib = target ? "$(TARGET).#$LIBEXT" : ""
  mfile = open("Makefile", "wb")
  mfile.print configuration(srcprefix)
  mfile.print %{
libpath = #{$LIBPATH.join(" ")}
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
STATIC_LIB = #{staticlib unless $static.nil?}

}
  install_dirs.each {|d| mfile.print("%-14s= %s\n" % d) if /^[[:upper:]]/ =~ d[0]}
  n = ($extout ? '$(RUBYARCHDIR)/' : '') + '$(TARGET).'
  mfile.print %{
TARGET_SO     = #{($extout ? '$(RUBYARCHDIR)/' : '')}$(DLLIB)
CLEANLIBS     = #{n}#{CONFIG['DLEXT']} #{n}il? #{n}tds #{n}map
CLEANOBJS     = *.#{$OBJEXT} *.#{$LIBEXT} *.s[ol] *.pdb *.exp *.bak

all:		#{target ? $extout ? "install" : "$(DLLIB)" : "Makefile"}
static:		$(STATIC_LIB)#{$extout ? " install-rb" : ""}
}
  mfile.print CLEANINGS
  dirs = []
  mfile.print "install: install-so install-rb\n\n"
  sodir = (dir = "$(RUBYARCHDIR)").dup
  mfile.print("install-so: #{dir}\n")
  if target
    f = "$(DLLIB)"
    dest = "#{dir}/#{f}"
    mfile.print "install-so: #{dest}\n"
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
    end
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
	mfile.print("#{dest}: #{f}\n\t$(#{$extout ? 'COPY' : 'INSTALL_DATA'}) ")
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
  mfile.print "$(DLLIB): ", (makedef ? "$(DEFFILE) " : ""), "$(OBJS)\n\t"
  mfile.print "@-$(RM) $@\n\t"
  mfile.print "@-$(MAKEDIRS) $(@D)\n\t" if $extout
  mfile.print LINK_SO, "\n\n"
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
	elsif RULE_SUBST and /\A[$\w][^#]*:/ =~ line
	  line.gsub!(%r"(\s)(?!\.)([^$(){}+=:\s\/\\,]+)(?=\s|\z)") {$1 + RULE_SUBST % $2}
	end
	depout << line
      end
      while line = dfile.gets()
	line.gsub!(/\.o\b/, ".#{$OBJEXT}")
	line.gsub!(/\$\(hdrdir\)\/config.h/, $config_h) if $config_h
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
    mfile.print depout
  else
    headers = %w[ruby.h defines.h]
    if RULE_SUBST
      headers.each {|h| h.sub!(/.*/) {|*m| RULE_SUBST % m}}
    end
    headers << $config_h if $config_h
    mfile.print "$(OBJS): ", headers.join(' '), "\n"
  end

  $makefile_created = true
ensure
  mfile.close if mfile
end

def init_mkmf(config = CONFIG)
  $makefile_created = false
  $arg_config = []
  $enable_shared = config['ENABLE_SHARED'] == 'yes'
  $defs = []
  $CFLAGS = with_config("cflags", arg_config("CFLAGS", config["CFLAGS"])).dup
  $ARCH_FLAG = with_config("arch_flag", arg_config("ARCH_FLAG", config["ARCH_FLAG"])).dup
  $CPPFLAGS = with_config("cppflags", arg_config("CPPFLAGS", config["CPPFLAGS"])).dup
  $LDFLAGS = (with_config("ldflags") || "").dup
  $INCFLAGS = "-I$(topdir)"
  $DLDFLAGS = with_config("dldflags", arg_config("DLDFLAGS", config["DLDFLAGS"])).dup
  $LIBEXT = config['LIBEXT'].dup
  $OBJEXT = config["OBJEXT"].dup
  $LIBS = "#{config['LIBS']} #{config['DLDLIBS']}"
  $LIBRUBYARG = ""
  $LIBRUBYARG_STATIC = config['LIBRUBYARG_STATIC']
  $LIBRUBYARG_SHARED = config['LIBRUBYARG_SHARED']
  $LIBPATH = $extmk ? ["$(topdir)"] : CROSS_COMPILING ? [] : ["$(libdir)"]
  $INSTALLFILES = nil

  $objs = nil
  $srcs = nil
  $libs = ""
  if $enable_shared or Config.expand(config["LIBRUBY"].dup) != Config.expand(config["LIBRUBY_A"].dup)
    $LIBRUBYARG = config['LIBRUBYARG']
  end

  $LOCAL_LIBS = ""

  $cleanfiles = config_string('CLEANFILES') {|s| Shellwords.shellwords(s)} || []
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

def mkmf_failed(path)
  unless $makefile_created or File.exist?("Makefile")
    opts = $arg_config.collect {|t, n| "\t#{t}#{"=#{n}" if n}\n"}
    abort "*** #{path} failed ***\n" + FailedMessage + opts.join
  end
end

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
  Shellwords.shellwords(s).each do |s|
    /(.*?)(?:=(.*))/ =~ s
    hdr << "#define #$1 #$2"
  end
end
config_string('COMMON_HEADERS') do |s|
  Shellwords.shellwords(s).each {|s| hdr << "#include <#{s}>"}
end
COMMON_HEADERS = (hdr.join("\n") unless hdr.empty?)
COMMON_LIBS = config_string('COMMON_LIBS', &split) || []

COMPILE_RULES = config_string('COMPILE_RULES', &split) || %w[.%s.%s:]
RULE_SUBST = config_string('RULE_SUBST')
COMPILE_C = config_string('COMPILE_C') || '$(CC) $(CFLAGS) $(CPPFLAGS) -c $<'
COMPILE_CXX = config_string('COMPILE_CXX') || '$(CXX) $(CXXFLAGS) $(CPPFLAGS) -c $<'
TRY_LINK = config_string('TRY_LINK') ||
  "$(CC) #{OUTFLAG}conftest $(INCFLAGS) -I$(hdrdir) $(CPPFLAGS) " \
  "$(CFLAGS) $(src) $(LIBPATH) $(LDFLAGS) $(ARCH_FLAG) $(LOCAL_LIBS) $(LIBS)"
LINK_SO = config_string('LINK_SO') ||
  if CONFIG["DLEXT"] == $OBJEXT
    "ld $(DLDFLAGS) -r -o $@ $(OBJS)\n"
  else
    "$(LDSHARED) $(DLDFLAGS) $(LIBPATH) #{OUTFLAG}$@ " \
    "$(OBJS) $(LOCAL_LIBS) $(LIBS)"
  end
LIBPATHFLAG = config_string('LIBPATHFLAG') || ' -L"%s"'
RPATHFLAG = config_string('RPATHFLAG') || ''
LIBARG = config_string('LIBARG') || '-l%s'

sep = File::ALT_SEPARATOR ? ":/=#{File::ALT_SEPARATOR}" : ''
CLEANINGS = "
clean:
		@-$(RM) $(CLEANLIBS#{sep}) $(CLEANOBJS#{sep}) $(CLEANFILES#{sep})

distclean:	clean
		@-$(RM) Makefile extconf.h conftest.* mkmf.log
		@-$(RM) core ruby$(EXEEXT) *~ $(DISTCLEANFILES#{sep})

realclean:	distclean
"

if not $extmk and /\A(extconf|makefile).rb\z/ =~ File.basename($0)
  END {mkmf_failed($0)}
end
