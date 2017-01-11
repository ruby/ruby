#!./miniruby

# Used by "make runruby", configure, and by hand to run a locally-built Ruby
# with correct environment variables and arguments.

show = false
precommand = []
while arg = ARGV[0]
  break ARGV.shift if arg == '--'
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
    precommand.concat(value ? (Shellwords.shellwords(value) unless value == "no") : %w"gdb --args")
  when re =~ "precommand"
    require 'shellwords'
    precommand.concat(Shellwords.shellwords(value))
  when re =~ "show"
    show = true
  else
    break
  end
  ARGV.shift
end

unless defined?(File.realpath)
  def File.realpath(*args)
    Dir.chdir(expand_path(*args)) do
      Dir.pwd
    end
  end
end

srcdir ||= File.realpath('..', File.dirname(__FILE__))
archdir ||= '.'

abs_archdir = File.expand_path(archdir)
$:.unshift(abs_archdir)

config = File.read(conffile = File.join(abs_archdir, 'rbconfig.rb'))
config.sub!(/^(\s*)RUBY_VERSION\b.*(\sor\s*)\n.*\n/, '')
config = Module.new {module_eval(config, conffile)}::RbConfig::CONFIG

ruby = File.join(archdir, config["RUBY_INSTALL_NAME"]+config['EXEEXT'])
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

env = {}

runner = File.join(abs_archdir, "ruby-runner#{config['EXEEXT']}")
runner = File.expand_path(ruby) unless File.exist?(runner)
env["RUBY"] = runner
env["PATH"] = [abs_archdir, ENV["PATH"]].compact.join(File::PATH_SEPARATOR)

if e = ENV["RUBYLIB"]
  libs |= e.split(File::PATH_SEPARATOR)
end
env["RUBYLIB"] = $:.replace(libs).join(File::PATH_SEPARATOR)

libruby_so = File.join(abs_archdir, config['LIBRUBY_SO'])
if File.file?(libruby_so)
  if e = config['LIBPATHENV'] and !e.empty?
    env[e] = [abs_archdir, ENV[e]].compact.join(File::PATH_SEPARATOR)
  end
  if e = config['PRELOADENV']
    e = nil if e.empty?
    e ||= "LD_PRELOAD" if /linux/ =~ RUBY_PLATFORM
  end
  if e
    env[e] = [libruby_so, ENV[e]].compact.join(File::PATH_SEPARATOR)
  end
end

ENV.update env

cmd = [ruby]
cmd.concat(ARGV)
cmd.unshift(*precommand) unless precommand.empty?
cmd.push(:close_others => false)

if show
  require 'shellwords'
  env.each {|k,v| puts "#{k}=#{v}"}
  puts Shellwords.join(cmd)
end

exec(*cmd)
