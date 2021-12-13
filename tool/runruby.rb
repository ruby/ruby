#!./miniruby

# Used by "make runruby", configure, and by hand to run a locally-built Ruby
# with correct environment variables and arguments.

show = false
precommand = []
srcdir = File.realpath('..', File.dirname(__FILE__))
case
when ENV['RUNRUBY_USE_GDB'] == 'true'
  debugger = :gdb
when ENV['RUNRUBY_USE_LLDB'] == 'true'
  debugger = :lldb
when ENV['RUNRUBY_YJIT_STATS']
  use_yjit_stat = true
end
while arg = ARGV[0]
  break ARGV.shift if arg == '--'
  case arg
  when '-C',  /\A-C(.+)/m
    ARGV.shift
    Dir.chdir($1 || ARGV.shift)
    next
  end
  /\A--([-\w]+)(?:=(.*))?\z/ =~ arg or break
  arg, value = $1, $2
  re = Regexp.new('\A'+arg.gsub(/\w+\b/, '\&\\w*')+'\z', "i")
  case
  when re =~ "srcdir"
    srcdir = value
  when re =~ "archdir"
    archdir = value
  when re =~ "cpu"
    precommand << "arch" << "-arch" << value
  when re =~ "extout"
    extout = value
  when re =~ "pure"
    # obsolete switch do nothing
  when re =~ "debugger"
    require 'shellwords'
    case value
    when nil
      debugger = :gdb
    when "lldb"
      debugger = :lldb
    when "no"
    else
      debugger = Shellwords.shellwords(value)
    end and precommand |= [:debugger]
  when re =~ "precommand"
    require 'shellwords'
    precommand.concat(Shellwords.shellwords(value))
  when re =~ "show"
    show = true
  when re =~ "chdir"
    Dir.chdir(value)
  else
    break
  end
  ARGV.shift
end

unless defined?(File.realpath)
  def File.realpath(*args)
    path = expand_path(*args)
    if File.stat(path).directory?
      Dir.chdir(path) {Dir.pwd}
    else
      dir, base = File.split(path)
      File.join(Dir.chdir(dir) {Dir.pwd}, base)
    end
  end
end

begin
  conffile = File.realpath('rbconfig.rb', archdir)
rescue Errno::ENOENT => e
  # retry if !archdir and ARGV[0] and File.directory?(archdir = ARGV.shift)
  abort "#$0: rbconfig.rb not found, use --archdir option"
end

abs_archdir = File.dirname(conffile)
archdir ||= abs_archdir
$:.unshift(abs_archdir)

config = File.read(conffile)
config.sub!(/^(\s*)RUBY_VERSION\b.*(\sor\s*)\n.*\n/, '')
config = Module.new {module_eval(config, conffile)}::RbConfig::CONFIG

install_name = config["RUBY_INSTALL_NAME"]+config['EXEEXT']
ruby = File.join(archdir, install_name)
unless File.exist?(ruby)
  abort "#{ruby} is not found.\nTry `make' first, then `make test', please.\n"
end

libs = [abs_archdir]
extout ||= config["EXTOUT"]
if extout
  abs_extout = File.expand_path(extout, abs_archdir)
  libs << File.expand_path("common", abs_extout) << File.expand_path(config['arch'], abs_extout)
end
libs << File.expand_path("lib", srcdir)
config["bindir"] = abs_archdir

env = {
  # Test with the smallest possible machine stack sizes.
  # These values are clamped to machine-dependent minimum values in vm_core.h
  'RUBY_THREAD_MACHINE_STACK_SIZE' => '1',
  'RUBY_FIBER_MACHINE_STACK_SIZE' => '1',
}

runner = File.join(abs_archdir, "exe/#{install_name}")
runner = nil unless File.exist?(runner)
abs_ruby = runner || File.expand_path(ruby)
env["RUBY"] = abs_ruby
env["GEM_PATH"] = env["GEM_HOME"] = File.expand_path(".bundle", srcdir)
env["GEM_COMMAND"] = "#{abs_ruby} -rrubygems #{srcdir}/bin/gem --backtrace"
env["PATH"] = [File.dirname(abs_ruby), abs_archdir, ENV["PATH"]].compact.join(File::PATH_SEPARATOR)

if e = ENV["RUBYLIB"]
  libs |= e.split(File::PATH_SEPARATOR)
end
env["RUBYLIB"] = $:.replace(libs).join(File::PATH_SEPARATOR)

libruby_so = File.join(abs_archdir, config['LIBRUBY_SO'])
if File.file?(libruby_so)
  if e = config['LIBPATHENV'] and !e.empty?
    env[e] = [abs_archdir, ENV[e]].compact.join(File::PATH_SEPARATOR)
  end
  unless runner
    if e = config['PRELOADENV']
      e = nil if e.empty?
      e ||= "LD_PRELOAD" if /linux/ =~ RUBY_PLATFORM
    end
    if e
      env[e] = [libruby_so, ENV[e]].compact.join(File::PATH_SEPARATOR)
    end
  end
end

ENV.update env

if debugger
  case debugger
  when :gdb, nil
    debugger = %W'gdb -x #{srcdir}/.gdbinit'
    if File.exist?(gdb = 'run.gdb') or
      File.exist?(gdb = File.join(abs_archdir, 'run.gdb'))
      debugger.push('-x', gdb)
    end
    debugger << '--args'
  when :lldb
    debugger = ['lldb', '-O', "command script import #{srcdir}/misc/lldb_cruby.py"]
    if File.exist?(lldb = 'run.lldb') or
      File.exist?(lldb = File.join(abs_archdir, 'run.lldb'))
      debugger.push('-s', lldb)
    end
    debugger << '--'
  end

  if idx = precommand.index(:debugger)
    precommand[idx, 1] = debugger
  else
    precommand.concat(debugger)
  end
end

cmd = [runner || ruby]
if use_yjit_stat
  cmd << '--yjit-stats'
end
cmd.concat(ARGV)
cmd.unshift(*precommand) unless precommand.empty?

if show
  require 'shellwords'
  env.each {|k,v| puts "#{k}=#{v}"}
  puts Shellwords.join(cmd)
end

exec(*cmd, close_others: false)
