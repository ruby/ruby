#
#   shell.rb - 
#   	$Release Version: 0.1 $
#   	$Revision: 1.1 $
#   	$Date: 1998/03/29 17:10:09 $
#   	by Keiju ISHITSUKA(Nippon Rational Inc.)
#
# --
#
#   
#

require "e2mmap"
require "ftools"

class Shell
  @RCS_ID='-$Id: shell.rb,v 1.1 1998/03/29 17:10:09 keiju Exp $-'

  module Error
    extend Exception2MessageMapper
    def_exception :DirStackEmpty, "Directory stack empty."
    def_exception :CanNotDefine, "Can't define method(%s, %s)."
    def_exception :CanNotMethodApply, "This method(%s) can't apply this type(%s)."
    def_exception :CommandNotFound, "Command not found(%s)."
  end
  include Error

  class << Shell
    attr :cascade, TRUE
    attr :debug, TRUE
    attr :verbose, TRUE

    alias cascade? cascade
    alias debug? debug
    alias verbose? verbose
  end

  def Shell.cd(path)
    sh = new
    sh.cd path
    sh
  end

  def Shell.default_system_path
    if @default_system_path
      @default_system_path
    else
      ENV["PATH"].split(":")
    end
  end

  def Shell.default_system_path=(path)
    @default_system_path = path
  end

  def Shell.default_record_separator
    if @default_record_separator
      @default_record_separator
    else
      $/
    end
  end

  def Shell.default_record_separator=(rs)
    @default_record_separator = rs
  end

  @cascade = TRUE
  @debug = FALSE
  @verbose = TRUE

  def initialize
    @cwd = Dir.pwd
    @dir_stack = []
    @umask = nil

    @system_commands = {}

    @system_path = Shell.default_system_path
    @record_separator = Shell.default_record_separator

    @verbose = Shell.verbose
  end

  attr :system_path
  
  def system_path=(path)
    @system_path = path
    @system_commands = {}
  end

  def rehash
    @system_commands = {}
  end

  attr :record_separator, TRUE

  attr :umask, TRUE
  attr :verbose, TRUE

  alias verbose? verbose

  def expand_path(path)
    if /^\// =~ path
      File.expand_path(path)
    else
      File.expand_path(File.join(@cwd, path))
    end
  end

  def effect_umask
    if @umask
      Thread.critical = TRUE
      save = File.umask
      begin
	yield
      ensure
	File.umask save
	Thread.critical = FALSE
      end
    else
      yield
    end
  end

  def [](pattern)
    Thread.critical=TRUE
    back = Dir.pwd
    begin
      Dir.chdir @cwd
      Dir[pattern]
    ensure
      Dir.chdir back
      Thread.critical = FALSE
    end
  end
  alias glob []

  def chdir(path = nil)
    path = "~" unless path
    @cwd = expand_path(path)
    @system_commands.clear
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
      @cwd = expand_path(path)
    else
      if pop = @dir_stack.pop
	@dir_stack.push @cwd
	chdir pop
      else
	Shell.fail DirStackEmpty
      end
    end
  end
  alias pushd pushdir

  def popdir
    if pop = @dir_stack.pop
      @cwd = pop
    else
      Shell.fail DirStackEmpty
    end
  end
  alias popd popdir

  attr :cwd
  alias dir cwd
  alias getwd cwd
  alias pwd cwd
  
  def foreach(path = nil, *rs)
    path = "." unless path
    path = expand_path(path)

    if File.directory?(path)
      Dir.foreach(path){|fn| yield fn}
    else
      IO.foreach(path, *rs){|l| yield l}
    end
  end

  def mkdir(path)
    Dir.mkdir(expand_path(path))
  end
  
  #
  # `mode' is effective iff `path' is specifying a file.
  #
  def open(path, mode)
    path = expand_path(path)
    if File.directory?(path)
      Dir.open(path)
    else
      effect_umask do
	File.open(path, mode)
      end
    end
  end
#  public :open

  def rmdir(path)
    Dir.rmdir(expand_path(path))
  end

  def unlink(path)
    path = expand_path(path)
    if File.directory?(path)
      Dir.unlink(path)
    else
      IO.unlink(path)
    end
  end

  #
  # command extension
  #   command_specs = [[command_name, [arguments,...]]]
  # FILENAME* -> expand_path(filename*)
  # \*FILENAME* -> filename*.collect{|fn| expand_path(fn)}.join(", ")
  #
  def Shell.def_commands(delegation_class, command_specs)
    for meth, args in command_specs
      arg_str = args.collect{|arg| arg.downcase}.join(", ")
      call_arg_str = args.collect{
	|arg|
	case arg
	when /^(FILENAME.*)$/
	  format("expand_path(%s)", $1.downcase)
	when /^(\*FILENAME.*)$/
	  # \*FILENAME* -> filenames.collect{|fn| expand_path(fn)}.join(", ")
	  $1.downcase + '.collect{|fn| expand_path(fn)}'
	else
	  arg
	end
      }.join(", ")
      d = %Q[
        def #{meth}(#{arg_str})
	  #{delegation_class}.#{meth}(#{call_arg_str})
        end
      ]
      if debug?
	print d
      elsif verbose?
	print "Define #{meth}(#{arg_str})\n"
      end
      eval d
    end
  end

  #
  # File methods
  #	open/foreach/unlink are defined elsewhere.
  #
  normal_delegation_file_methods = [
    ["atime", ["FILENAME"]],
    ["basename", ["fn", "*opts"]],
    ["chmod", ["mode", "*FILENAMES"]], 
    ["chown", ["owner", "group", "FILENAME"]],
    ["ctime", ["group", "*FILENAMES"]],
    ["delete", ["*FILENAMES"]],
    ["dirname", ["FILENAME"]],
    ["ftype", ["FILENAME"]],
    ["join", ["*items"]],
    ["link", ["FILENAME_O", "FILENAME_N"]],
    ["lstat", ["FILENAME"]],
    ["mtime", ["FILENAME"]],
    ["readlink", ["FILENAME"]],
    ["rename", ["FILENAME_FROM", "FILENAME_TO"]],
    ["size", ["FILENAME"]],
    ["split", ["pathname"]],
    ["stat", ["FILENAME"]],
    ["symlink", ["FILENAME_O", "FILENAME_N"]],
    ["truncate", ["FILENAME", "length"]],
    ["utime", ["atime", "mtime", "*FILENAMES"]]]
  def_commands(File,
	       normal_delegation_file_methods)
  alias rm delete

  # FileTest method
  def_commands(FileTest, 
	       FileTest.singleton_methods.collect{|m| [m, ["FILENAME"]]})

  # ftools methods
  normal_delegation_ftools_methods = [
    ["syscopy", ["FILENAME_FROM", "FILENAME_TO"]],
    ["copy", ["FILENAME_FROM", "FILENAME_TO"]],
    ["move", ["FILENAME_FROM", "FILENAME_TO"]],
    ["compare", ["FILENAME_FROM", "FILENAME_TO"]],
    ["safe_unlink", ["*FILENAMES"]],
    ["makedirs", ["*FILENAMES"]],
#    ["chmod", ["mode", "*FILENAMES"]],
    ["install", ["FILENAME_FROM", "FILENAME_TO", "mode"]],
  ]
  def_commands(File,
	       normal_delegation_ftools_methods)
  alias cmp compare
  alias mv move
  alias cp copy
  alias rm_f safe_unlink
  alias mkpath makedirs

  # test function
  alias top_level_test test
  def test(command, file1, file2 = nil)
    if file2
      top_level_test command, expand_path(file1), expand_path(file2)
    else
      top_level_test command, expand_path(file1)
    end
  end

  # shell functions
  def echo(*strings)
    Echo.new(self, *strings)
  end

  def cat(*filenames)
    Cat.new(self, *filenames)
  end

  def tee(file)
    Tee.new(self, file)
  end

#   def sort(*filenames)
#     Sort.new(self, *filenames)
#   end

  def system(command, *opts)
    System.new(self, find_system_command(command), *opts)
  end

  #
  # search for command, raise exception if not found.
  #
  def find_system_command(command)
    return command if /^\// =~ command
    case path = @system_commands[command]
    when String
      if sh.exists?(path)
	return path
      else
	Shell.fail CommandNotFound, command
      end
    when FALSE
      Shell.fail CommandNotFound, command
    end

    for p in @system_path
      path = join(p, command)
      if FileTest.exists?(path)
	@system_commands[command] = path
	return path
      end
    end
    @system_commands[command] = FALSE
    Shell.fail CommandNotFound, command
  end

  #
  # define command as singleton method.
  #
  def def_system_command(command, path = command)
    d = "
      def self.#{command}(*opts)
	System.new(self, find_system_command('#{path}'), *opts)
      end
    "
    begin
      eval d
    rescue
      print "Can't define self.#{command} path: #{path}\n" if debug? or verbose?
      Shell.fail CanNotDefine, comamnd, path
    end
    if debug?
      print d
    elsif verbose?
      print "Define self.#{command} path: #{path}\n"
    end
  end

  #
  # define command as Shell method.
  #
  def Shell.def_system_command(command, path = command)
    d = "
      def #{command}(*opts)
	System.new(self, '#{path}', *opts)
      end
    "
    begin
      eval d
    rescue
      print "Can't define #{command} path: #{path}\n" if debug? or verbose?
      Shell.fail CanNotDefine, comamnd, path
    end
    if debug?
      print d
    elsif verbose?
      print "Define #{command} path: #{path}\n"
    end
  end

  #
  # defines commands on default_path.  if the method is already defined,
  # do nothing.  as default, methods are prefixed by "sys_".
  # invalid characters as method name are converted into "_".
  #
  def Shell.install_system_command(pre = "sys_")
    defined_meth = {}
    for m in Shell.methods
      defined_meth[m] = TRUE
    end
    sh = Shell.new
    for path in Shell.default_path
      next unless sh.directory? path
      sh.cd path
      sh.foreach do
	|cn|
	if !defined_meth[pre + cn] && sh.file?(cn) && sh.executable?(cn)
	  command = (pre + cn).gsub(/\W/, "_").sub(/^([0-9])/, '_\1')
	  begin
	    def_system_command(command, sh.expand_path(cn))
	  rescue
            printf("Warning: Can't define %s path: %s\n",
		   comamnd,
		   cn) unless debug? or verbose?
	  end
	  defined_meth[command] = command
	end
      end
    end
  end

  #
  # Filter
  # required method:
  #    each()
  class Filter
    include Enumerable
    include Error

    def initialize(sh)
      @shell = sh
    end

    def input=(filter)
      @input = filter
    end

    def each(rs = nil)
      rs = @shell.record_separator unless rs
      if @input
	@input.each(rs){|l| yield l}
      end
    end

    def < (src)
      case src
      when String
	cat = Cat.new(@shell, src)
	cat | self
      when IO
	@input = src
	self
      else
	Filter.fail CanNotMethodApply, "<", to.type
      end
    end

    def > (to)
      case to
      when String
	dst = @shell.open(to, "w")
	begin
	  each(){|l| dst << l}
	ensure
	  dst.close
	end
      when IO
	each(){|l| to << l}
      else
	Filter.fail CanNotMethodApply, ">", to.type
      end
      self
    end

    def >> (to)
      case to
      when String
	dst = @shell.open(to, "a")
	begin
	  each(){|l| dst << l}
	ensure
	  dst.close
	end
      when IO
	each(){|l| to << l}
      else
	Filter.fail CanNotMethodApply, ">>", to.type
      end
      self
    end

    def | (filter)
      filter.input = self
      filter
    end

    def method_missing(method, *args)
      if Shell.cascade? and @shell.respond_to?(method)
	self | @shell.send(method, *args)
      else
	super
      end
    end

    def to_a
      ary = []
      each(){|l| ary.push l}
      ary
    end

    def to_s
      str = ""
      each(){|l| str.concat l}
      str
    end
  end

  class Echo < Filter
    def initialize(sh, *strings)
      super sh
      @strings = strings
    end
    
    def each(rs = nil)
      rs =  @shell.record_separator unless rs
      for str  in @strings
	yield str + rs
      end
    end
  end

  class Cat < Filter
    def initialize(sh, *filenames)
      super sh
      @cat_files = filenames
    end

    def each(rs = nil)
      if @cat_files.empty?
	super
      else
	for src in @cat_files
	  @shell.foreach(src, rs){|l| yield l}
	end
      end
    end
  end

#   class Sort < Cat
#     def initialize(sh, *filenames)
#       super
#     end
#
#     def each(rs = nil)
#       ary = []
#       super{|l|	ary.push l}
#       for l in ary.sort!
# 	yield l
#       end
#     end
#   end

  class Tee < Filter
    def initialize(sh, filename)
      super sh
      @to_filename = filename
    end

    def each(rs = nil)
      to = @shell.open(@to_filename, "w")
      begin
	super{|l| to << l; yield l}
      ensure
	to.close
      end
    end
  end

  class System < Filter
    def initialize(sh, command, *opts)
      require "socket"
      
      super(sh)
#      @sock_me, @sock_peer = Socket.pair(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
      @pipe_me_in, @pipe_peer_out = pipe
      @pipe_peer_in, @pipe_me_out = pipe
      begin
	pid = fork {
#	  @sock_me.close
	  @pipe_me_in.close
	  @pipe_me_out.close
#	  STDIN.reopen(@sock_peer)
#	  STDOUT.reopen(@sock_peer)
	  STDIN.reopen(@pipe_peer_in)
	  STDOUT.reopen(@pipe_peer_out)
	  fork {
	    exec(command + " " + opts.join(" "))
	  }
	  exit
	}
#	print pid; $stdout.flush
      ensure
#       sock_peer.close
        @pipe_peer_in.close
	@pipe_peer_out.close
	begin
	  Process.waitpid(pid, nil)
	rescue Errno::ECHILD
	end
      end
    end

    def each(rs = nil)
      rs = @shell.record_separator unless rs
      begin
	th_o = Thread.start{
	  super{|l| @pipe_me_out.print l}
#	  @sock_me.shutdown(0)
	  @pipe_me_out.close
	}
	begin
	  @pipe_me_in.each(rs) do
	    |l|
#	    print l
	    yield l
	  end
	ensure
	  th_o.exit
	end
      ensure
#	@sock_peer.close unless @sock_peer.closed?
#	@sock_me.close
	@pipe_me_in.close
      end
    end
  end
end
