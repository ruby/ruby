# frozen_string_literal: false
#
#   shell/command-controller.rb -
#       $Release Version: 0.7 $
#       $Revision$
#       by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#

require "e2mmap"

require "shell/error"
require "shell/filter"
require "shell/system-command"
require "shell/builtin-command"

class Shell
  # In order to execute a command on your OS, you need to define it as a
  # Shell method.
  #
  # Alternatively, you can execute any command via
  # Shell::CommandProcessor#system even if it is not defined.
  class CommandProcessor

    #
    # initialize of Shell and related classes.
    #
    m = [:initialize, :expand_path]
    if Object.methods.first.kind_of?(String)
      NoDelegateMethods = m.collect{|x| x.id2name}
    else
      NoDelegateMethods = m
    end

    def self.initialize

      install_builtin_commands

      # define CommandProcessor#methods to Shell#methods and Filter#methods
      for m in CommandProcessor.instance_methods(false) - NoDelegateMethods
        add_delegate_command_to_shell(m)
      end

      def self.method_added(id)
        add_delegate_command_to_shell(id)
      end
    end

    #
    # include run file.
    #
    def self.run_config
      rc = "~/.rb_shell"
      begin
        load File.expand_path(rc) if ENV.key?("HOME")
      rescue LoadError, Errno::ENOENT
      rescue
        print "load error: #{rc}\n"
        print $!.class, ": ", $!, "\n"
        for err in $@[0, $@.size - 2]
          print "\t", err, "\n"
        end
      end
    end

    def initialize(shell)
      @shell = shell
      @system_commands = {}
    end

    #
    # CommandProcessor#expand_path(path)
    #     path:   String
    #     return: String
    #   returns the absolute path for <path>
    #
    def expand_path(path)
      @shell.expand_path(path)
    end

    # call-seq:
    #   foreach(path, record_separator) -> Enumerator
    #   foreach(path, record_separator) { block }
    #
    # See IO.foreach when +path+ is a file.
    #
    # See Dir.foreach when +path+ is a directory.
    #
    def foreach(path = nil, *rs)
      path = "." unless path
      path = expand_path(path)

      if File.directory?(path)
        Dir.foreach(path){|fn| yield fn}
      else
        IO.foreach(path, *rs){|l| yield l}
      end
    end

    # call-seq:
    #   open(path, mode, permissions) -> Enumerator
    #   open(path, mode, permissions) { block }
    #
    # See IO.open when +path+ is a file.
    #
    # See Dir.open when +path+ is a directory.
    #
    def open(path, mode = nil, perm = 0666, &b)
      path = expand_path(path)
      if File.directory?(path)
        Dir.open(path, &b)
      else
        if @shell.umask
          f = File.open(path, mode, perm)
          File.chmod(perm & ~@shell.umask, path)
          if block_given?
            f.each(&b)
          end
          f
        else
          File.open(path, mode, perm, &b)
        end
      end
    end

    # call-seq:
    #   unlink(path)
    #
    # See IO.unlink when +path+ is a file.
    #
    # See Dir.unlink when +path+ is a directory.
    #
    def unlink(path)
      @shell.check_point

      path = expand_path(path)
      if File.directory?(path)
        Dir.unlink(path)
      else
        IO.unlink(path)
      end
      Void.new(@shell)
    end

    # See Shell::CommandProcessor#test
    alias top_level_test test
    # call-seq:
    #   test(command, file1, file2) ->  true or false
    #   [command, file1, file2] ->  true or false
    #
    # Tests if the given +command+ exists in +file1+, or optionally +file2+.
    #
    # Example:
    #     sh[?e, "foo"]
    #     sh[:e, "foo"]
    #     sh["e", "foo"]
    #     sh[:exists?, "foo"]
    #     sh["exists?", "foo"]
    #
    def test(command, file1, file2=nil)
      file1 = expand_path(file1)
      file2 = expand_path(file2) if file2
      command = command.id2name if command.kind_of?(Symbol)

      case command
      when Integer
        if file2
          top_level_test(command, file1, file2)
        else
          top_level_test(command, file1)
        end
      when String
        if command.size == 1
          if file2
            top_level_test(command, file1, file2)
          else
            top_level_test(command, file1)
          end
        else
          if file2
            FileTest.send(command, file1, file2)
          else
            FileTest.send(command, file1)
          end
        end
      end
    end
    # See Shell::CommandProcessor#test
    alias [] test

    # call-seq:
    #   mkdir(path)
    #
    # Same as Dir.mkdir, except multiple directories are allowed.
    def mkdir(*path)
      @shell.check_point
      notify("mkdir #{path.join(' ')}")

      perm = nil
      if path.last.kind_of?(Integer)
        perm = path.pop
      end
      for dir in path
        d = expand_path(dir)
        if perm
          Dir.mkdir(d, perm)
        else
          Dir.mkdir(d)
        end
        File.chmod(d, 0666 & ~@shell.umask) if @shell.umask
      end
      Void.new(@shell)
    end

    # call-seq:
    #   rmdir(path)
    #
    # Same as Dir.rmdir, except multiple directories are allowed.
    def rmdir(*path)
      @shell.check_point
      notify("rmdir #{path.join(' ')}")

      for dir in path
        Dir.rmdir(expand_path(dir))
      end
      Void.new(@shell)
    end

    # call-seq:
    #   system(command, *options) -> SystemCommand
    #
    # Executes the given +command+ with the +options+ parameter.
    #
    # Example:
    #     print sh.system("ls", "-l")
    #     sh.system("ls", "-l") | sh.head > STDOUT
    #
    def system(command, *opts)
      if opts.empty?
        if command =~ /\*|\?|\{|\}|\[|\]|<|>|\(|\)|~|&|\||\\|\$|;|'|`|"|\n/
          return SystemCommand.new(@shell, find_system_command("sh"), "-c", command)
        else
          command, *opts = command.split(/\s+/)
        end
      end
      SystemCommand.new(@shell, find_system_command(command), *opts)
    end

    # call-seq:
    #   rehash
    #
    # Clears the command hash table.
    def rehash
      @system_commands = {}
    end

    def check_point # :nodoc:
      @shell.process_controller.wait_all_jobs_execution
    end
    alias finish_all_jobs check_point # :nodoc:

    # call-seq:
    #   transact { block }
    #
    # Executes a block as self
    #
    # Example:
    #   sh.transact { system("ls", "-l") | head > STDOUT }
    def transact(&block)
      begin
        @shell.instance_eval(&block)
      ensure
        check_point
      end
    end

    # call-seq:
    #   out(device) { block }
    #
    # Calls <code>device.print</code> on the result passing the _block_ to
    # #transact
    def out(dev = STDOUT, &block)
      dev.print transact(&block)
    end

    # call-seq:
    #   echo(*strings) ->  Echo
    #
    # Returns a Echo object, for the given +strings+
    def echo(*strings)
      Echo.new(@shell, *strings)
    end

    # call-seq:
    #   cat(*filename) ->  Cat
    #
    # Returns a Cat object, for the given +filenames+
    def cat(*filenames)
      Cat.new(@shell, *filenames)
    end

    #   def sort(*filenames)
    #     Sort.new(self, *filenames)
    #   end
    # call-seq:
    #   glob(pattern) ->  Glob
    #
    # Returns a Glob filter object, with the given +pattern+ object
    def glob(pattern)
      Glob.new(@shell, pattern)
    end

    def append(to, filter)
      case to
      when String
        AppendFile.new(@shell, to, filter)
      when IO
        AppendIO.new(@shell, to, filter)
      else
        Shell.Fail Error::CantApplyMethod, "append", to.class
      end
    end

    # call-seq:
    #   tee(file) ->  Tee
    #
    # Returns a Tee filter object, with the given +file+ command
    def tee(file)
      Tee.new(@shell, file)
    end

    # call-seq:
    #   concat(*jobs) ->  Concat
    #
    # Returns a Concat object, for the given +jobs+
    def concat(*jobs)
      Concat.new(@shell, *jobs)
    end

    # %pwd, %cwd -> @pwd
    def notify(*opts)
      Shell.notify(*opts) {|mes|
        yield mes if iterator?

        mes.gsub!("%pwd", "#{@cwd}")
        mes.gsub!("%cwd", "#{@cwd}")
      }
    end

    #
    # private functions
    #
    def find_system_command(command)
      return command if /^\// =~ command
      case path = @system_commands[command]
      when String
        if exists?(path)
          return path
        else
          Shell.Fail Error::CommandNotFound, command
        end
      when false
        Shell.Fail Error::CommandNotFound, command
      end

      for p in @shell.system_path
        path = join(p, command)
        begin
          st = File.stat(path)
        rescue SystemCallError
          next
        else
          next unless st.executable? and !st.directory?
          @system_commands[command] = path
          return path
        end
      end
      @system_commands[command] = false
      Shell.Fail Error::CommandNotFound, command
    end

    # call-seq:
    #   def_system_command(command, path)  ->  Shell::SystemCommand
    #
    # Defines a command, registering +path+ as a Shell method for the given
    # +command+.
    #
    #     Shell::CommandProcessor.def_system_command "ls"
    #       #=> Defines ls.
    #
    #     Shell::CommandProcessor.def_system_command "sys_sort", "sort"
    #       #=> Defines sys_sort as sort
    #
    def self.def_system_command(command, path = command)
      begin
        eval((d = %Q[def #{command}(*opts)
                  SystemCommand.new(@shell, '#{path}', *opts)
               end]), nil, __FILE__, __LINE__ - 1)
      rescue SyntaxError
        Shell.notify "warn: Can't define #{command} path: #{path}."
      end
      Shell.notify "Define #{command} path: #{path}.", Shell.debug?
      Shell.notify("Definition of #{command}: ", d,
             Shell.debug.kind_of?(Integer) && Shell.debug > 1)
    end

    # call-seq:
    #   undef_system_command(command) ->  self
    #
    # Undefines a command
    def self.undef_system_command(command)
      command = command.id2name if command.kind_of?(Symbol)
      remove_method(command)
      Shell.module_eval{remove_method(command)}
      Filter.module_eval{remove_method(command)}
      self
    end

    @alias_map = {}
    # Returns a list of aliased commands
    def self.alias_map
      @alias_map
    end
    # call-seq:
    #   alias_command(alias, command, *options) ->  self
    #
    # Creates a command alias at the given +alias+ for the given +command+,
    # passing any +options+ along with it.
    #
    #     Shell::CommandProcessor.alias_command "lsC", "ls", "-CBF", "--show-control-chars"
    #     Shell::CommandProcessor.alias_command("lsC", "ls"){|*opts| ["-CBF", "--show-control-chars", *opts]}
    #
    def self.alias_command(ali, command, *opts)
      ali = ali.id2name if ali.kind_of?(Symbol)
      command = command.id2name if command.kind_of?(Symbol)
      begin
        if iterator?
          @alias_map[ali.intern] = proc

          eval((d = %Q[def #{ali}(*opts)
                          @shell.__send__(:#{command},
                                          *(CommandProcessor.alias_map[:#{ali}].call *opts))
                        end]), nil, __FILE__, __LINE__ - 1)

        else
           args = opts.collect{|opt| '"' + opt + '"'}.join(",")
           eval((d = %Q[def #{ali}(*opts)
                          @shell.__send__(:#{command}, #{args}, *opts)
                        end]), nil, __FILE__, __LINE__ - 1)
        end
      rescue SyntaxError
        Shell.notify "warn: Can't alias #{ali} command: #{command}."
        Shell.notify("Definition of #{ali}: ", d)
        raise
      end
      Shell.notify "Define #{ali} command: #{command}.", Shell.debug?
      Shell.notify("Definition of #{ali}: ", d,
             Shell.debug.kind_of?(Integer) && Shell.debug > 1)
      self
    end

    # call-seq:
    #   unalias_command(alias)  ->  self
    #
    # Unaliases the given +alias+ command.
    def self.unalias_command(ali)
      ali = ali.id2name if ali.kind_of?(Symbol)
      @alias_map.delete ali.intern
      undef_system_command(ali)
    end

    # :nodoc:
    #
    # Delegates File and FileTest methods into Shell, including the following
    # commands:
    #
    # * Shell#blockdev?(file)
    # * Shell#chardev?(file)
    # * Shell#directory?(file)
    # * Shell#executable?(file)
    # * Shell#executable_real?(file)
    # * Shell#exist?(file)/Shell#exists?(file)
    # * Shell#file?(file)
    # * Shell#grpowned?(file)
    # * Shell#owned?(file)
    # * Shell#pipe?(file)
    # * Shell#readable?(file)
    # * Shell#readable_real?(file)
    # * Shell#setgid?(file)
    # * Shell#setuid?(file)
    # * Shell#size(file)/Shell#size?(file)
    # * Shell#socket?(file)
    # * Shell#sticky?(file)
    # * Shell#symlink?(file)
    # * Shell#writable?(file)
    # * Shell#writable_real?(file)
    # * Shell#zero?(file)
    # * Shell#syscopy(filename_from, filename_to)
    # * Shell#copy(filename_from, filename_to)
    # * Shell#move(filename_from, filename_to)
    # * Shell#compare(filename_from, filename_to)
    # * Shell#safe_unlink(*filenames)
    # * Shell#makedirs(*filenames)
    # * Shell#install(filename_from, filename_to, mode)
    #
    # And also, there are some aliases for convenience:
    #
    # * Shell#cmp	<- Shell#compare
    # * Shell#mv	<- Shell#move
    # * Shell#cp	<- Shell#copy
    # * Shell#rm_f	<- Shell#safe_unlink
    # * Shell#mkpath	<- Shell#makedirs
    #
    def self.def_builtin_commands(delegation_class, command_specs)
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
        d = %Q[def #{meth}(#{arg_str})
                    #{delegation_class}.#{meth}(#{call_arg_str})
                 end]
        Shell.notify "Define #{meth}(#{arg_str})", Shell.debug?
        Shell.notify("Definition of #{meth}: ", d,
                     Shell.debug.kind_of?(Integer) && Shell.debug > 1)
        eval d
      end
    end

    # call-seq:
    #     install_system_commands(prefix = "sys_")
    #
    # Defines all commands in the Shell.default_system_path as Shell method,
    # all with given +prefix+ appended to their names.
    #
    # Any invalid character names are converted to +_+, and errors are passed
    # to Shell.notify.
    #
    # Methods already defined are skipped.
    def self.install_system_commands(pre = "sys_")
      defined_meth = {}
      for m in Shell.methods
        defined_meth[m] = true
      end
      sh = Shell.new
      for path in Shell.default_system_path
        next unless sh.directory? path
        sh.cd path
        sh.foreach do
          |cn|
          if !defined_meth[pre + cn] && sh.file?(cn) && sh.executable?(cn)
            command = (pre + cn).gsub(/\W/, "_").sub(/^([0-9])/, '_\1')
            begin
              def_system_command(command, sh.expand_path(cn))
            rescue
              Shell.notify "warn: Can't define #{command} path: #{cn}"
            end
            defined_meth[command] = command
          end
        end
      end
    end

    def self.add_delegate_command_to_shell(id) # :nodoc:
      id = id.intern if id.kind_of?(String)
      name = id.id2name
      if Shell.method_defined?(id)
        Shell.notify "warn: override definition of Shell##{name}."
        Shell.notify "warn: alias Shell##{name} to Shell##{name}_org.\n"
        Shell.module_eval "alias #{name}_org #{name}"
      end
      Shell.notify "method added: Shell##{name}.", Shell.debug?
      Shell.module_eval(%Q[def #{name}(*args, &block)
                            begin
                              @command_processor.__send__(:#{name}, *args, &block)
                            rescue Exception
                              $@.delete_if{|s| /:in `__getobj__'$/ =~ s} #`
                              $@.delete_if{|s| /^\\(eval\\):/ =~ s}
                            raise
                            end
                          end], __FILE__, __LINE__)

      if Shell::Filter.method_defined?(id)
        Shell.notify "warn: override definition of Shell::Filter##{name}."
        Shell.notify "warn: alias Shell##{name} to Shell::Filter##{name}_org."
        Filter.module_eval "alias #{name}_org #{name}"
      end
      Shell.notify "method added: Shell::Filter##{name}.", Shell.debug?
      Filter.module_eval(%Q[def #{name}(*args, &block)
                            begin
                              self | @shell.__send__(:#{name}, *args, &block)
                            rescue Exception
                              $@.delete_if{|s| /:in `__getobj__'$/ =~ s} #`
                              $@.delete_if{|s| /^\\(eval\\):/ =~ s}
                            raise
                            end
                          end], __FILE__, __LINE__)
    end

    # Delegates File methods into Shell, including the following commands:
    #
    # * Shell#atime(file)
    # * Shell#basename(file, *opt)
    # * Shell#chmod(mode, *files)
    # * Shell#chown(owner, group, *file)
    # * Shell#ctime(file)
    # * Shell#delete(*file)
    # * Shell#dirname(file)
    # * Shell#ftype(file)
    # * Shell#join(*file)
    # * Shell#link(file_from, file_to)
    # * Shell#lstat(file)
    # * Shell#mtime(file)
    # * Shell#readlink(file)
    # * Shell#rename(file_from, file_to)
    # * Shell#split(file)
    # * Shell#stat(file)
    # * Shell#symlink(file_from, file_to)
    # * Shell#truncate(file, length)
    # * Shell#utime(atime, mtime, *file)
    #
    def self.install_builtin_commands
      # method related File.
      # (exclude open/foreach/unlink)
      normal_delegation_file_methods = [
        ["atime", ["FILENAME"]],
        ["basename", ["fn", "*opts"]],
        ["chmod", ["mode", "*FILENAMES"]],
        ["chown", ["owner", "group", "*FILENAME"]],
        ["ctime", ["FILENAMES"]],
        ["delete", ["*FILENAMES"]],
        ["dirname", ["FILENAME"]],
        ["ftype", ["FILENAME"]],
        ["join", ["*items"]],
        ["link", ["FILENAME_O", "FILENAME_N"]],
        ["lstat", ["FILENAME"]],
        ["mtime", ["FILENAME"]],
        ["readlink", ["FILENAME"]],
        ["rename", ["FILENAME_FROM", "FILENAME_TO"]],
        ["split", ["pathname"]],
        ["stat", ["FILENAME"]],
        ["symlink", ["FILENAME_O", "FILENAME_N"]],
        ["truncate", ["FILENAME", "length"]],
        ["utime", ["atime", "mtime", "*FILENAMES"]]]

      def_builtin_commands(File, normal_delegation_file_methods)
      alias_method :rm, :delete

      # method related FileTest
      def_builtin_commands(FileTest,
                   FileTest.singleton_methods(false).collect{|m| [m, ["FILENAME"]]})

    end

  end
end
