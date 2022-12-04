#!/usr/bin/env ruby
#
# rexe - Ruby Command Line Executor Filter
#
# Inspired by https://github.com/thisredone/rb

# frozen_string_literal: true


require 'bundler'
require 'date'
require 'optparse'
require 'ostruct'
require 'shellwords'

class Rexe

  VERSION = '1.5.1'

  PROJECT_URL = 'https://github.com/keithrbennett/rexe'


  module Helpers

    # Try executing code. If error raised, print message (but not stack trace) & exit -1.
    def try
      begin
        yield
      rescue Exception => e
        unless e.class == SystemExit
          $stderr.puts("rexe: #{e}")
          $stderr.puts("Use the -h option to get help.")
          exit(-1)
        end
      end
    end
  end


  class Options < Struct.new(
      :input_filespec,
      :input_format,
      :input_mode,
      :loads,
      :output_format,
      :output_format_tty,
      :output_format_block,
      :requires,
      :log_format,
      :noop)


    def initialize
      super
      clear
    end


    def clear
      self.input_filespec = nil
      self.input_format        = :none
      self.input_mode          = :none
      self.output_format       = :none
      self.output_format_tty   = :none
      self.output_format_block = :none
      self.loads               = []
      self.requires            = []
      self.log_format          = :none
      self.noop                = false
    end
  end





  class Lookups
    def input_modes
      @input_modes ||= {
          'l' => :line,
          'e' => :enumerator,
          'b' => :one_big_string,
          'n' => :none
      }
    end


    def input_formats
      @input_formats ||=  {
          'j' => :json,
          'm' => :marshal,
          'n' => :none,
          'y' => :yaml,
      }
    end


    def input_parsers
      @input_parsers ||= {
          json:    ->(string)  { JSON.parse(string) },
          marshal: ->(string)  { Marshal.load(string) },
          none:    ->(string)  { string },
          yaml:    ->(string)  { YAML.load(string) },
      }
    end


    def output_formats
      @output_formats ||= {
          'a' => :amazing_print,
          'i' => :inspect,
          'j' => :json,
          'J' => :pretty_json,
          'm' => :marshal,
          'n' => :none,
          'p' => :puts,         # default
          'P' => :pretty_print,
          's' => :to_s,
          'y' => :yaml,
      }
    end


    def formatters
      @formatters ||=  {
          amazing_print: ->(obj)  { obj.ai + "\n" },
          inspect:       ->(obj)  { obj.inspect + "\n" },
          json:          ->(obj)  { obj.to_json },
          marshal:       ->(obj)  { Marshal.dump(obj) },
          none:          ->(_obj) { nil },
          pretty_json:   ->(obj)  { JSON.pretty_generate(obj) },
          pretty_print:  ->(obj)  { obj.pretty_inspect },
          puts:          ->(obj)  { require 'stringio'; sio = StringIO.new; sio.puts(obj); sio.string },
          to_s:          ->(obj)  { obj.to_s + "\n" },
          yaml:          ->(obj)  { obj.to_yaml },
      }
    end


    def format_requires
      @format_requires ||= {
          json:          'json',
          pretty_json:   'json',
          amazing_print: 'amazing_print',
          pretty_print:  'pp',
          yaml:          'yaml'
      }
    end
  end



  class CommandLineParser

    include Helpers

    attr_reader :lookups, :options

    def initialize
      @lookups = Lookups.new
      @options = Options.new
    end


    # Inserts contents of REXE_OPTIONS environment variable at the beginning of ARGV.
    private def prepend_environment_options
      env_opt_string = ENV['REXE_OPTIONS']
      if env_opt_string
        args_to_prepend = Shellwords.shellsplit(env_opt_string)
        ARGV.unshift(args_to_prepend).flatten!
      end
    end


    private def add_format_requires_to_requires_list
      formats = [options.input_format, options.output_format, options.log_format]
      requires = formats.map { |format| lookups.format_requires[format] }.uniq.compact
      requires.each { |r| options.requires << r }
    end


    private def help_text
      unless @help_text
        @help_text ||= <<~HEREDOC

          rexe -- Ruby Command Line Executor/Filter -- v#{VERSION} -- #{PROJECT_URL}

          Executes Ruby code on the command line,
          optionally automating management of standard input and standard output,
          and optionally parsing input and formatting output with YAML, JSON, etc.

          rexe [options] [Ruby source code]

          Options:

          -c  --clear_options        Clear all previous command line options specified up to now
          -f  --input_file           Use this file instead of stdin for preprocessed input;
                                     if filespec has a YAML and JSON file extension,
                                     sets input format accordingly and sets input mode to -mb
          -g  --log_format FORMAT    Log format, logs to stderr, defaults to -gn (none)
                                     (see -o for format options)
          -h, --help                 Print help and exit
          -i, --input_format FORMAT  Input format, defaults to -in (None)
                                       -ij  JSON
                                       -im  Marshal
                                       -in  None (default)
                                       -iy  YAML
          -l, --load RUBY_FILE(S)    Ruby file(s) to load, comma separated;
                                       ! to clear all, or precede a name with '-' to remove
          -m, --input_mode MODE      Input preprocessing mode (determines what `self` will be)
                                     defaults to -mn (none)
                                       -ml  line; each line is ingested as a separate string
                                       -me  enumerator (each_line on STDIN or File)
                                       -mb  big string; all lines combined into one string
                                       -mn  none (default); no input preprocessing;
                                            self is an Object.new
          -n, --[no-]noop            Do not execute the code (useful with -g);
                                     For true: yes, true, y, +; for false: no, false, n
          -o, --output_format FORMAT Output format, defaults to -on (no output):
                                       -oa  Amazing Print
                                       -oi  Inspect
                                       -oj  JSON
                                       -oJ  Pretty JSON
                                       -om  Marshal
                                       -on  No Output (default)
                                       -op  Puts
                                       -oP  Pretty Print
                                       -os  to_s
                                       -oy  YAML
                                       If 2 letters are provided, 1st is for tty devices, 2nd for block
          --project-url              Outputs project URL on Github, then exits
          -r, --require REQUIRE(S)   Gems and built-in libraries to require, comma separated;
                                       ! to clear all, or precede a name with '-' to remove
          -v, --version              Prints version and exits

          ---------------------------------------------------------------------------------------

          In many cases you will need to enclose your source code in single or double quotes.

          If source code is not specified, it will default to 'self',
          which is most likely useful only in a filter mode (-ml, -me, -mb).

          If there is a .rexerc file in your home directory, it will be run as Ruby code
          before processing the input.

          If there is a REXE_OPTIONS environment variable, its content will be prepended
          to the command line so that you can specify options implicitly
          (e.g. `export REXE_OPTIONS="-r amazing_print,yaml"`)

      HEREDOC

        @help_text.freeze
      end

      @help_text
    end


    # File file input mode; detects the input mode (JSON, YAML, or None) from the extension.
    private def autodetect_file_format(filespec)
      extension = File.extname(filespec).downcase
      if extension == '.json'
        :json
      elsif extension == '.yml' || extension == '.yaml'
        :yaml
      else
        :none
      end
    end


    private def open_resource(resource_identifier)
      command = case (`uname`.chomp)
                when 'Darwin'
                  'open'
                when 'Linux'
                  'xdg-open'
                else
                  'start'
                end

      `#{command} #{resource_identifier}`
    end


  # Using 'optparse', parses the command line.
    # Settings go into this instance's properties (see Struct declaration).
    def parse

      prepend_environment_options

      OptionParser.new do |parser|

        parser.on('-c', '--clear_options', "Clear all previous command line options") do |v|
          options.clear
        end

        parser.on('-f', '--input_file FILESPEC',
            'Use this file instead of stdin; autodetects YAML and JSON file extensions') do |v|
          unless File.exist?(v)
            raise "File #{v} does not exist."
          end
          options.input_filespec = v
          options.input_format = autodetect_file_format(v)
          if [:json, :yaml].include?(options.input_format)
            options.input_mode = :one_big_string
          end
        end

        parser.on('-g', '--log_format FORMAT', 'Log format, logs to stderr, defaults to none (see -o for format options)') do |v|
          options.log_format = lookups.output_formats[v]
          if options.log_format.nil?
            raise("Output mode was '#{v}' but must be one of #{lookups.output_formats.keys}.")
          end
        end

        parser.on("-h", "--help", "Show help") do |_help_requested|
          puts help_text
          exit
        end

        parser.on('-i', '--input_format FORMAT',
                  'Mode with which to parse input values (n = none (default), j = JSON, m = Marshal, y = YAML') do |v|

          options.input_format = lookups.input_formats[v]
          if options.input_format.nil?
            raise("Input mode was '#{v}' but must be one of #{lookups.input_formats.keys}.")
          end
        end

        parser.on('-l', '--load RUBY_FILE(S)', 'Ruby file(s) to load, comma separated, or ! to clear') do |v|
          if v == '!'
            options.loads.clear
          else
            loadfiles = v.split(',').map(&:strip).map { |s| File.expand_path(s) }
            removes, adds = loadfiles.partition { |filespec| filespec[0] == '-' }

            existent, nonexistent = adds.partition { |filespec| File.exists?(filespec) }
            if nonexistent.any?
              raise("\nDid not find the following files to load: #{nonexistent}\n\n")
            else
              existent.each { |filespec| options.loads << filespec }
            end

            removes.each { |filespec| options.loads -= [filespec[1..-1]] }
          end
        end

        parser.on('-m', '--input_mode MODE',
                  'Mode with which to handle input (-ml, -me, -mb, -mn (default)') do |v|

          options.input_mode = lookups.input_modes[v]
          if options.input_mode.nil?
            raise("Input mode was '#{v}' but must be one of #{lookups.input_modes.keys}.")
          end
        end

        # See https://stackoverflow.com/questions/54576873/ruby-optionparser-short-code-for-boolean-option
        # for an excellent explanation of this optparse incantation.
        # According to the answer, valid options are:
        # -n no, -n yes, -n false, -n true, -n n, -n y, -n +, but not -n -.
        parser.on('-n', '--[no-]noop [FLAG]', TrueClass, "Do not execute the code (useful with -g)") do |v|
          options.noop = (v.nil? ? true : v)
        end

        parser.on('-o', '--output_format FORMAT',
                  'Mode with which to format values for output (`-o` + [aijJmnpsy])') do |v|
          options.output_format_tty   = lookups.output_formats[v[0]]
          options.output_format_block = lookups.output_formats[v[-1]]
          options.output_format = ($stdout.tty? ? options.output_format_tty : options.output_format_block)
          if [options.output_format_tty, options.output_format_block].include?(nil)
            raise("Bad output mode '#{v}'; each must be one of #{lookups.output_formats.keys}.")
          end
        end

        parser.on('-r', '--require REQUIRE(S)',
                  'Gems and built-in libraries (e.g. shellwords, yaml) to require, comma separated, or ! to clear') do |v|
          if v == '!'
            options.requires.clear
          else
            v.split(',').map(&:strip).each do |r|
              if r[0] == '-'
                options.requires -= [r[1..-1]]
              else
                options.requires << r
              end
            end
          end
        end

        parser.on('-v', '--version', 'Print version') do
          puts VERSION
          exit(0)
        end

        # Undocumented feature: open Github project with default web browser on a Mac
        parser.on('', '--open-project') do
          open_resource(PROJECT_URL)
          exit(0)
        end

        parser.on('', '--project-url') do
          puts PROJECT_URL
          exit(0)
        end

      end.parse!

      # We want to do this after all options have been processed because we don't want any clearing of the
      # options (by '-c', etc.) to result in exclusion of these needed requires.
      add_format_requires_to_requires_list

      options.requires = options.requires.sort.uniq
      options.loads.uniq!

      options

    end
  end


  class Main

    include Helpers

    attr_reader :callable, :input_parser, :lookups,
                :options, :output_formatter,
                :log_formatter, :start_time, :user_source_code


    def initialize
      @lookups = Lookups.new
      @start_time = DateTime.now
    end


    private def load_global_config_if_exists
      filespec = File.join(Dir.home, '.rexerc')
      load(filespec) if File.exists?(filespec)
    end


    private def init_parser_and_formatters
      @input_parser     = lookups.input_parsers[options.input_format]
      @output_formatter = lookups.formatters[options.output_format]
      @log_formatter    = lookups.formatters[options.log_format]
    end


    # Executes the user specified code in the manner appropriate to the input mode.
    # Performs any optionally specified parsing on input and formatting on output.
    private def execute(eval_context_object, code)
      if options.input_format != :none && options.input_mode != :none
        eval_context_object = input_parser.(eval_context_object)
      end

      value = eval_context_object.instance_eval(&code)

      unless options.output_format == :none
        print output_formatter.(value)
      end
    rescue Errno::EPIPE
      exit(-13)
    end


    # The global $RC (Rexe Context) OpenStruct is available in your user code.
    # In order to make it possible to access this object in your loaded files, we are not creating
    # it here; instead we add properties to it. This way, you can initialize an OpenStruct yourself
    # in your loaded code and it will still work. If you do that, beware, any properties you add will be
    # included in the log output. If the to_s of your added objects is large, that might be a pain.
    private def init_rexe_context
      $RC ||= OpenStruct.new
      $RC.count         = 0
      $RC.rexe_version  = VERSION
      $RC.start_time    = start_time.iso8601
      $RC.source_code   = user_source_code
      $RC.options       = options.to_h

      def $RC.i; count end  # `i` aliases `count` so you can more concisely get the count in your user code
    end


    private def create_callable
      eval("Proc.new { #{user_source_code} }")
    end


    private def lookup_action(mode)
      input = options.input_filespec ? File.open(options.input_filespec) : STDIN
      {
          line:           -> { input.each { |l| execute(l.chomp, callable);            $RC.count += 1 } },
          enumerator:     -> { execute(input.each_line, callable);                     $RC.count += 1 },
          one_big_string: -> { big_string = input.read; execute(big_string, callable); $RC.count += 1 },
          none:           -> { execute(Object.new, callable) }
      }.fetch(mode)
    end


    private def output_log_entry
      if options.log_format != :none
        $RC.duration_secs = Time.now - start_time.to_time
        STDERR.puts(log_formatter.($RC.to_h))
      end
    end


    # Bypasses Bundler's restriction on loading gems
    # (see https://stackoverflow.com/questions/55144094/bundler-doesnt-permit-using-gems-in-project-home-directory)
    private def require!(the_require)
      begin
        require the_require
      rescue LoadError => error
        gem_path = `gem which #{the_require}`
        if gem_path.chomp.strip.empty?
          raise error # re-raise the error, can't fix it
        else
          load_dir = File.dirname(gem_path)
          $LOAD_PATH += load_dir
          require the_require
        end
      end
    end


    # This class' entry point.
    def call

      try do

        @options = CommandLineParser.new.parse

        options.requires.each { |r| require!(r) }
        load_global_config_if_exists
        options.loads.each { |file| load(file) }

        @user_source_code = ARGV.join(' ')
        @user_source_code = 'self' if @user_source_code == ''

        @callable = create_callable

        init_rexe_context
        init_parser_and_formatters

        # This is where the user's source code will be executed; the action will in turn call `execute`.
        lookup_action(options.input_mode).call unless options.noop

        output_log_entry
      end
    end
  end
end


def bundler_run(&block)
  # This used to be an unconditional call to with_clean_env but that method is now deprecated:
  # [DEPRECATED] `Bundler.with_clean_env` has been deprecated in favor of `Bundler.with_unbundled_env`.
  # If you instead want the environment before bundler was originally loaded,
  # use `Bundler.with_original_env`

  if Bundler.respond_to?(:with_unbundled_env)
    Bundler.with_unbundled_env { block.call }
  else
    Bundler.with_clean_env { block.call }
  end
end


bundler_run { Rexe::Main.new.call }
