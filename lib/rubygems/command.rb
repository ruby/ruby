#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'optparse'

require 'rubygems/user_interaction'

module Gem

  # Base class for all Gem commands.  When creating a new gem command, define
  # #arguments, #defaults_str, #description and #usage (as appropriate).
  class Command

    include UserInteraction

    # The name of the command.
    attr_reader :command

    # The options for the command.
    attr_reader :options

    # The default options for the command.
    attr_accessor :defaults

    # The name of the command for command-line invocation.
    attr_accessor :program_name

    # A short description of the command.
    attr_accessor :summary

    # Initializes a generic gem command named +command+.  +summary+ is a short
    # description displayed in `gem help commands`.  +defaults+ are the
    # default options.  Defaults should be mirrored in #defaults_str, unless
    # there are none.
    #
    # Use add_option to add command-line switches.
    def initialize(command, summary=nil, defaults={})
      @command = command
      @summary = summary
      @program_name = "gem #{command}"
      @defaults = defaults
      @options = defaults.dup
      @option_groups = Hash.new { |h,k| h[k] = [] }
      @parser = nil
      @when_invoked = nil
    end

    # True if +long+ begins with the characters from +short+.
    def begins?(long, short)
      return false if short.nil?
      long[0, short.length] == short
    end

    # Override to provide command handling.
    def execute
      fail "Generic command has no actions"
    end

    # Get all gem names from the command line.
    def get_all_gem_names
      args = options[:args]

      if args.nil? or args.empty? then
        raise Gem::CommandLineError,
              "Please specify at least one gem name (e.g. gem build GEMNAME)"
      end

      gem_names = args.select { |arg| arg !~ /^-/ }
    end

    # Get the single gem name from the command line.  Fail if there is no gem
    # name or if there is more than one gem name given.
    def get_one_gem_name
      args = options[:args]

      if args.nil? or args.empty? then
        raise Gem::CommandLineError,
             "Please specify a gem name on the command line (e.g. gem build GEMNAME)"
      end

      if args.size > 1 then
        raise Gem::CommandLineError,
              "Too many gem names (#{args.join(', ')}); please specify only one"
      end

      args.first
    end

    # Get a single optional argument from the command line.  If more than one
    # argument is given, return only the first. Return nil if none are given.
    def get_one_optional_argument
      args = options[:args] || []
      args.first
    end

    # Override to provide details of the arguments a command takes.
    # It should return a left-justified string, one argument per line.
    def arguments
      ""
    end

    # Override to display the default values of the command
    # options. (similar to +arguments+, but displays the default
    # values).
    def defaults_str
      ""
    end

    # Override to display a longer description of what this command does.
    def description
      nil
    end

    # Override to display the usage for an individual gem command.
    def usage
      program_name
    end

    # Display the help message for the command.
    def show_help
      parser.program_name = usage
      say parser
    end

    # Invoke the command with the given list of arguments.
    def invoke(*args)
      handle_options(args)
      if options[:help]
        show_help
      elsif @when_invoked
        @when_invoked.call(options)
      else
        execute
      end
    end

    # Call the given block when invoked.
    #
    # Normal command invocations just executes the +execute+ method of
    # the command.  Specifying an invocation block allows the test
    # methods to override the normal action of a command to determine
    # that it has been invoked correctly.
    def when_invoked(&block)
      @when_invoked = block
    end

    # Add a command-line option and handler to the command.
    #
    # See OptionParser#make_switch for an explanation of +opts+.
    #
    # +handler+ will be called with two values, the value of the argument and
    # the options hash.
    def add_option(*opts, &handler) # :yields: value, options
      group_name = Symbol === opts.first ? opts.shift : :options

      @option_groups[group_name] << [opts, handler]
    end

    # Remove previously defined command-line argument +name+.
    def remove_option(name)
      @option_groups.each do |_, option_list|
        option_list.reject! { |args, _| args.any? { |x| x =~ /^#{name}/ } }
      end
    end

    # Merge a set of command options with the set of default options
    # (without modifying the default option hash).
    def merge_options(new_options)
      @options = @defaults.clone
      new_options.each do |k,v| @options[k] = v end
    end

    # True if the command handles the given argument list.
    def handles?(args)
      begin
        parser.parse!(args.dup)
        return true
      rescue
        return false
      end
    end

    # Handle the given list of arguments by parsing them and recording
    # the results.
    def handle_options(args)
      args = add_extra_args(args)
      @options = @defaults.clone
      parser.parse!(args)
      @options[:args] = args
    end

    def add_extra_args(args)
      result = []
      s_extra = Command.specific_extra_args(@command)
      extra = Command.extra_args + s_extra
      while ! extra.empty?
        ex = []
        ex << extra.shift
        ex << extra.shift if extra.first.to_s =~ /^[^-]/
        result << ex if handles?(ex)
      end
      result.flatten!
      result.concat(args)
      result
    end

    private

    # Create on demand parser.
    def parser
      create_option_parser if @parser.nil?
      @parser
    end

    def create_option_parser
      @parser = OptionParser.new

      @parser.separator("")
      regular_options = @option_groups.delete :options

      configure_options "", regular_options

      @option_groups.sort_by { |n,_| n.to_s }.each do |group_name, option_list|
        configure_options group_name, option_list
      end

      configure_options "Common", Command.common_options

      @parser.separator("")
      unless arguments.empty?
        @parser.separator("  Arguments:")
        arguments.split(/\n/).each do |arg_desc|
          @parser.separator("    #{arg_desc}")
        end
        @parser.separator("")
      end

      @parser.separator("  Summary:")
      wrap(@summary, 80 - 4).split("\n").each do |line|
        @parser.separator("    #{line.strip}")
      end

      if description then
        formatted = description.split("\n\n").map do |chunk|
          wrap(chunk, 80 - 4)
        end.join("\n")

        @parser.separator ""
        @parser.separator "  Description:"
        formatted.split("\n").each do |line|
          @parser.separator "    #{line.rstrip}"
        end
      end

      unless defaults_str.empty?
        @parser.separator("")
        @parser.separator("  Defaults:")
        defaults_str.split(/\n/).each do |line|
          @parser.separator("    #{line}")
        end
      end
    end

    def configure_options(header, option_list)
      return if option_list.nil? or option_list.empty?

      header = header.to_s.empty? ? '' : "#{header} "
      @parser.separator "  #{header}Options:"

      option_list.each do |args, handler|
        dashes = args.select { |arg| arg =~ /^-/ }
        @parser.on(*args) do |value|
          handler.call(value, @options)
        end
      end

      @parser.separator ''
    end

    # Wraps +text+ to +width+
    def wrap(text, width)
      text.gsub(/(.{1,#{width}})( +|$\n?)|(.{1,#{width}})/, "\\1\\3\n")
    end

    ##################################################################
    # Class methods for Command.
    class << self
      def common_options
        @common_options ||= []
      end

      def add_common_option(*args, &handler)
        Gem::Command.common_options << [args, handler]
      end

      def extra_args
        @extra_args ||= []
      end

      def extra_args=(value)
        case value
        when Array
          @extra_args = value
        when String
          @extra_args = value.split
        end
      end

      # Return an array of extra arguments for the command.  The extra
      # arguments come from the gem configuration file read at program
      # startup.
      def specific_extra_args(cmd)
        specific_extra_args_hash[cmd]
      end

      # Add a list of extra arguments for the given command.  +args+
      # may be an array or a string to be split on white space.
      def add_specific_extra_args(cmd,args)
        args = args.split(/\s+/) if args.kind_of? String
        specific_extra_args_hash[cmd] = args
      end

      # Accessor for the specific extra args hash (self initializing).
      def specific_extra_args_hash
        @specific_extra_args_hash ||= Hash.new do |h,k|
          h[k] = Array.new
        end
      end
    end

    # ----------------------------------------------------------------
    # Add the options common to all commands.

    add_common_option('-h', '--help',
      'Get help on this command') do
      |value, options|
      options[:help] = true
    end

    add_common_option('-V', '--[no-]verbose',
                      'Set the verbose level of output') do |value, options|
      # Set us to "really verbose" so the progress meter works
      if Gem.configuration.verbose and value then
        Gem.configuration.verbose = 1
      else
        Gem.configuration.verbose = value
      end
    end

    add_common_option('-q', '--quiet', 'Silence commands') do |value, options|
      Gem.configuration.verbose = false
    end

    # Backtrace and config-file are added so they show up in the help
    # commands.  Both options are actually handled before the other
    # options get parsed.

    add_common_option('--config-file FILE',
      "Use this config file instead of default") do
    end

    add_common_option('--backtrace',
      'Show stack backtrace on errors') do
    end

    add_common_option('--debug',
      'Turn on Ruby debugging') do
    end

    # :stopdoc:
    HELP = %{
      RubyGems is a sophisticated package manager for Ruby.  This is a
      basic help message containing pointers to more information.

        Usage:
          gem -h/--help
          gem -v/--version
          gem command [arguments...] [options...]

        Examples:
          gem install rake
          gem list --local
          gem build package.gemspec
          gem help install

        Further help:
          gem help commands            list all 'gem' commands
          gem help examples            show some examples of usage
          gem help platforms           show information about platforms
          gem help <COMMAND>           show help on COMMAND
                                         (e.g. 'gem help install')
        Further information:
          http://rubygems.rubyforge.org
    }.gsub(/^    /, "")

    # :startdoc:

  end # class

  # This is where Commands will be placed in the namespace
  module Commands; end

end
