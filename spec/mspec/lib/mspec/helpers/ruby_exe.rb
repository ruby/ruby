require 'mspec/guards/platform'
require 'mspec/helpers/tmp'

# The ruby_exe helper provides a wrapper for invoking the
# same Ruby interpreter with the same falgs as the one running
# the specs and getting the output from running the code.
# If +code+ is a file that exists, it will be run.
# Otherwise, +code+ should be Ruby code that will be run with
# the -e command line option. For example:
#
#   ruby_exe('path/to/some/file.rb')
#
# will be executed as
#
#   `#{RUBY_EXE} 'path/to/some/file.rb'`
#
# while
#
#   ruby_exe('puts "hello, world."')
#
# will be executed as
#
#   `#{RUBY_EXE} -e 'puts "hello, world."'`
#
# The ruby_exe helper also accepts an options hash with three
# keys: :options, :args and :env. For example:
#
#   ruby_exe('file.rb', :options => "-w",
#                       :args => "> file.txt",
#                       :env => { :FOO => "bar" })
#
# will be executed as
#
#   `#{RUBY_EXE} -w #{'file.rb'} > file.txt`
#
# with access to ENV["FOO"] with value "bar".
#
# If +nil+ is passed for the first argument, the command line
# will be built only from the options hash.
#
# If no arguments are passed to ruby_exe, it returns an Array
# containing the interpreter executable and the flags:
#
#    spawn(*ruby_exe, "-e", "puts :hello")
#
# This avoids spawning an extra shell, and ensure the pid returned by spawn
# corresponds to the ruby process and not the shell.
#
# The RUBY_EXE constant is setup by mspec automatically
# and is used by ruby_exe and ruby_cmd. The mspec runner script
# will set ENV['RUBY_EXE'] to the name of the executable used
# to invoke the mspec-run script. The value of RUBY_EXE will be
# constructed as follows:
#
#   1. the value of ENV['RUBY_EXE']
#   2. an explicit value based on RUBY_ENGINE
#   3. cwd/(RUBY_ENGINE + $(EXEEXT) || $(exeext) || '')
#   4. $(bindir)/$(RUBY_INSTALL_NAME)
#
# The value will only be used if the file exists and is executable.
# The flags will then be appended to the resulting value.
#
# These 4 ways correspond to the following scenarios:
#
#   1. Using the MSpec runner scripts, the name of the
#      executable is explicitly passed by ENV['RUBY_EXE']
#      so there is no ambiguity.
#
#  Otherwise, if using RSpec (or something else)
#
#   2. Running the specs while developing an alternative
#      Ruby implementation. This explicitly names the
#      executable in the development directory based on
#      the value of RUBY_ENGINE.
#   3. Running the specs within the source directory for
#      some implementation. (E.g. a local build directory.)
#   4. Running the specs against some installed Ruby
#      implementation.
#
# Additionally, the flags passed to mspec
# (with -T on the command line or in the config with set :flags)
# will be appended to RUBY_EXE so that the interpreter
# is always called with those flags.

def ruby_exe_options(option)
  case option
  when :env
    ENV['RUBY_EXE']
  when :engine
    case RUBY_ENGINE
    when 'rbx'
      "bin/rbx"
    when 'jruby'
      "bin/jruby"
    when 'maglev'
      "maglev-ruby"
    when 'topaz'
      "topaz"
    when 'ironruby'
      "ir"
    end
  when :name
    require 'rbconfig'
    bin = RUBY_ENGINE + (RbConfig::CONFIG['EXEEXT'] || RbConfig::CONFIG['exeext'] || '')
    File.join(".", bin)
  when :install_name
    require 'rbconfig'
    bin = RbConfig::CONFIG["RUBY_INSTALL_NAME"] || RbConfig::CONFIG["ruby_install_name"]
    bin << (RbConfig::CONFIG['EXEEXT'] || RbConfig::CONFIG['exeext'] || '')
    File.join(RbConfig::CONFIG['bindir'], bin)
  end
end

def resolve_ruby_exe
  [:env, :engine, :name, :install_name].each do |option|
    next unless exe = ruby_exe_options(option)

    if File.file?(exe) and File.executable?(exe)
      exe = File.expand_path(exe)
      exe = exe.tr('/', '\\') if PlatformGuard.windows?
      flags = ENV['RUBY_FLAGS']
      if flags and !flags.empty?
        return exe + ' ' + flags
      else
        return exe
      end
    end
  end
  raise Exception, "Unable to find a suitable ruby executable."
end

def ruby_exe(code = :not_given, opts = {})
  if opts[:dir]
    raise "ruby_exe(..., dir: dir) is no longer supported, use Dir.chdir"
  end

  if code == :not_given
    return RUBY_EXE.split(' ')
  end

  env = opts[:env] || {}
  saved_env = {}
  env.each do |key, value|
    key = key.to_s
    saved_env[key] = ENV[key] if ENV.key? key
    ENV[key] = value
  end

  escape = opts.delete(:escape)
  if code and !File.exist?(code) and escape != false
    tmpfile = tmp("rubyexe.rb")
    File.open(tmpfile, "w") { |f| f.write(code) }
    code = tmpfile
  end

  begin
    platform_is_not :opal do
      `#{ruby_cmd(code, opts)}`
    end
  ensure
    saved_env.each { |key, value| ENV[key] = value }
    env.keys.each do |key|
      key = key.to_s
      ENV.delete key unless saved_env.key? key
    end
    File.delete tmpfile if tmpfile
  end
end

def ruby_cmd(code, opts = {})
  body = code

  if opts[:escape]
    raise "escape: true is no longer supported in ruby_cmd, use ruby_exe or a fixture"
  end

  if code and !File.exist?(code)
    body = "-e #{code.inspect}"
  end

  [RUBY_EXE, opts[:options], body, opts[:args]].compact.join(' ')
end

unless Object.const_defined?(:RUBY_EXE) and RUBY_EXE
  RUBY_EXE = resolve_ruby_exe
end
