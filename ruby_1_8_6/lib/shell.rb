#
#   shell.rb - 
#   	$Release Version: 0.6.0 $
#   	$Revision: 1.8 $
#   	$Date: 2001/03/19 09:01:11 $
#   	by Keiju ISHITSUKA(Nippon Rational Inc.)
#
# --
#
#   
#

require "e2mmap"
require "thread"

require "shell/error"
require "shell/command-processor"
require "shell/process-controller"

class Shell
  @RCS_ID='-$Id: shell.rb,v 1.8 2001/03/19 09:01:11 keiju Exp keiju $-'

  include Error
  extend Exception2MessageMapper

#  @cascade = true
  # debug: true -> normal debug
  # debug: 1    -> eval definition debug
  # debug: 2    -> detail inspect debug
  @debug = false
  @verbose = true

  class << Shell
    attr :cascade, true
    attr :debug, true
    attr :verbose, true

#    alias cascade? cascade
    alias debug? debug
    alias verbose? verbose
    @verbose = true

    def debug=(val)
      @debug = val
      @verbose = val if val
    end

    def cd(path)
      sh = new
      sh.cd path
      sh
    end

    def default_system_path
      if @default_system_path
	@default_system_path
      else
	ENV["PATH"].split(":")
      end
    end

    def default_system_path=(path)
      @default_system_path = path
    end

    def default_record_separator
      if @default_record_separator
	@default_record_separator
      else
	$/
      end
    end

    def default_record_separator=(rs)
      @default_record_separator = rs
    end
  end

  def initialize
    @cwd = Dir.pwd
    @dir_stack = []
    @umask = nil

    @system_path = Shell.default_system_path
    @record_separator = Shell.default_record_separator

    @command_processor = CommandProcessor.new(self)
    @process_controller = ProcessController.new(self)

    @verbose = Shell.verbose
    @debug = Shell.debug
  end

  attr_reader :system_path

  def system_path=(path)
    @system_path = path
    rehash
  end

  attr :umask, true
  attr :record_separator, true

  attr :verbose, true
  attr :debug, true

  def debug=(val)
    @debug = val
    @verbose = val if val
  end

  alias verbose? verbose
  alias debug? debug

  attr_reader :command_processor
  attr_reader :process_controller

  def expand_path(path)
    File.expand_path(path, @cwd)
  end

  # Most Shell commands are defined via CommandProcessor

  #
  # Dir related methods
  #
  # Shell#cwd/dir/getwd/pwd
  # Shell#chdir/cd
  # Shell#pushdir/pushd
  # Shell#popdir/popd
  # Shell#mkdir
  # Shell#rmdir

  attr :cwd
  alias dir cwd
  alias getwd cwd
  alias pwd cwd

  attr :dir_stack
  alias dirs dir_stack

  # If called as iterator, it restores the current directory when the
  # block ends.
  def chdir(path = nil)
    if iterator?
      cwd_old = @cwd
      begin
	chdir(path)
	yield
      ensure
	chdir(cwd_old)
      end
    else
      path = "~" unless path
      @cwd = expand_path(path)
      notify "current dir: #{@cwd}"
      rehash
      self
    end
  end
  alias cd chdir

  def pushdir(path = nil)
    if iterator?
      pushdir(path)
      begin
	yield
      ensure
	popdir
      end
    elsif path
      @dir_stack.push @cwd
      chdir path
      notify "dir stack: [#{@dir_stack.join ', '}]"
      self
    else
      if pop = @dir_stack.pop
	@dir_stack.push @cwd
	chdir pop
	notify "dir stack: [#{@dir_stack.join ', '}]"
	self
      else
	Shell.Fail DirStackEmpty
      end
    end
  end
  alias pushd pushdir

  def popdir
    if pop = @dir_stack.pop
      chdir pop
      notify "dir stack: [#{@dir_stack.join ', '}]"
      self
    else
      Shell.Fail DirStackEmpty
    end
  end
  alias popd popdir


  #
  # process management
  #
  def jobs
    @process_controller.jobs
  end

  def kill(sig, command)
    @process_controller.kill_job(sig, command)
  end

  #
  # command definitions
  #
  def Shell.def_system_command(command, path = command)
    CommandProcessor.def_system_command(command, path)
  end

  def Shell.undef_system_command(command)
    CommandProcessor.undef_system_command(command)
  end

  def Shell.alias_command(ali, command, *opts, &block)
    CommandProcessor.alias_command(ali, command, *opts, &block)
  end

  def Shell.unalias_command(ali)
    CommandProcessor.unalias_command(ali)
  end

  def Shell.install_system_commands(pre = "sys_")
    CommandProcessor.install_system_commands(pre)
  end

  #
  def inspect
    if debug.kind_of?(Integer) && debug > 2
      super
    else
      to_s
    end
  end

  def self.notify(*opts, &block)
    Thread.exclusive do
    if opts[-1].kind_of?(String)
      yorn = verbose?
    else
      yorn = opts.pop
    end
    return unless yorn

    _head = true
    print opts.collect{|mes|
      mes = mes.dup
      yield mes if iterator?
      if _head
	_head = false
	"shell: " + mes
      else
	"       " + mes
      end
    }.join("\n")+"\n"
    end
  end

  CommandProcessor.initialize
  CommandProcessor.run_config
end
