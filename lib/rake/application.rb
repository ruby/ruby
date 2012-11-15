require 'shellwords'
require 'optparse'

require 'rake/task_manager'
require 'rake/thread_pool'
require 'rake/thread_history_display'
require 'rake/win32'

module Rake

  CommandLineOptionError = Class.new(StandardError)

  ######################################################################
  # Rake main application object.  When invoking +rake+ from the
  # command line, a Rake::Application object is created and run.
  #
  class Application
    include TaskManager

    # The name of the application (typically 'rake')
    attr_reader :name

    # The original directory where rake was invoked.
    attr_reader :original_dir

    # Name of the actual rakefile used.
    attr_reader :rakefile

    # Number of columns on the terminal
    attr_accessor :terminal_columns

    # List of the top level task names (task names from the command line).
    attr_reader :top_level_tasks

    DEFAULT_RAKEFILES = ['rakefile', 'Rakefile', 'rakefile.rb', 'Rakefile.rb'].freeze

    # Initialize a Rake::Application object.
    def initialize
      super
      @name = 'rake'
      @rakefiles = DEFAULT_RAKEFILES.dup
      @rakefile = nil
      @pending_imports = []
      @imported = []
      @loaders = {}
      @default_loader = Rake::DefaultLoader.new
      @original_dir = Dir.pwd
      @top_level_tasks = []
      add_loader('rb', DefaultLoader.new)
      add_loader('rf', DefaultLoader.new)
      add_loader('rake', DefaultLoader.new)
      @tty_output = STDOUT.tty?
      @terminal_columns = ENV['RAKE_COLUMNS'].to_i
    end

    # Run the Rake application.  The run method performs the following
    # three steps:
    #
    # * Initialize the command line options (+init+).
    # * Define the tasks (+load_rakefile+).
    # * Run the top level tasks (+top_level+).
    #
    # If you wish to build a custom rake command, you should call
    # +init+ on your application.  Then define any tasks.  Finally,
    # call +top_level+ to run your top level tasks.
    def run
      standard_exception_handling do
        init
        load_rakefile
        top_level
      end
    end

    # Initialize the command line parameters and app name.
    def init(app_name='rake')
      standard_exception_handling do
        @name = app_name
        handle_options
        collect_tasks
      end
    end

    # Find the rakefile and then load it and any pending imports.
    def load_rakefile
      standard_exception_handling do
        raw_load_rakefile
      end
    end

    # Run the top level tasks of a Rake application.
    def top_level
      run_with_threads do
        if options.show_tasks
          display_tasks_and_comments
        elsif options.show_prereqs
          display_prerequisites
        else
          top_level_tasks.each { |task_name| invoke_task(task_name) }
        end
      end
    end

    # Run the given block with the thread startup and shutdown.
    def run_with_threads
      thread_pool.gather_history if options.job_stats == :history

      yield

      thread_pool.join
      if options.job_stats
        stats = thread_pool.statistics
        puts "Maximum active threads: #{stats[:max_active_threads]}"
        puts "Total threads in play:  #{stats[:total_threads_in_play]}"
      end
      ThreadHistoryDisplay.new(thread_pool.history).show if options.job_stats == :history
    end

    # Add a loader to handle imported files ending in the extension
    # +ext+.
    def add_loader(ext, loader)
      ext = ".#{ext}" unless ext =~ /^\./
      @loaders[ext] = loader
    end

    # Application options from the command line
    def options
      @options ||= OpenStruct.new
    end

    # Return the thread pool used for multithreaded processing.
    def thread_pool             # :nodoc:
      @thread_pool ||= ThreadPool.new(options.thread_pool_size||FIXNUM_MAX)
    end

    # private ----------------------------------------------------------------

    def invoke_task(task_string)
      name, args = parse_task_string(task_string)
      t = self[name]
      t.invoke(*args)
    end

    def parse_task_string(string)
      if string =~ /^([^\[]+)(\[(.*)\])$/
        name = $1
        args = $3.split(/\s*,\s*/)
      else
        name = string
        args = []
      end
      [name, args]
    end

    # Provide standard exception handling for the given block.
    def standard_exception_handling
      begin
        yield
      rescue SystemExit => ex
        # Exit silently with current status
        raise
      rescue OptionParser::InvalidOption => ex
        $stderr.puts ex.message
        exit(false)
      rescue Exception => ex
        # Exit with error message
        display_error_message(ex)
        exit(false)
      end
    end

    # Display the error message that caused the exception.
    def display_error_message(ex)
      trace "#{name} aborted!"
      trace ex.message
      if options.backtrace
        trace ex.backtrace.join("\n")
      else
        trace Backtrace.collapse(ex.backtrace)
      end
      trace "Tasks: #{ex.chain}" if has_chain?(ex)
      trace "(See full trace by running task with --trace)" unless options.backtrace
    end

    # Warn about deprecated usage.
    #
    # Example:
    #    Rake.application.deprecate("import", "Rake.import", caller.first)
    #
    def deprecate(old_usage, new_usage, call_site)
      return if options.ignore_deprecate
      $stderr.puts "WARNING: '#{old_usage}' is deprecated.  " +
        "Please use '#{new_usage}' instead.\n" +
        "    at #{call_site}"
    end

    # Does the exception have a task invocation chain?
    def has_chain?(exception)
      exception.respond_to?(:chain) && exception.chain
    end
    private :has_chain?

    # True if one of the files in RAKEFILES is in the current directory.
    # If a match is found, it is copied into @rakefile.
    def have_rakefile
      @rakefiles.each do |fn|
        if File.exist?(fn)
          others = Rake.glob(fn, File::FNM_CASEFOLD)
          return others.size == 1 ? others.first : fn
        elsif fn == ''
          return fn
        end
      end
      return nil
    end

    # True if we are outputting to TTY, false otherwise
    def tty_output?
      @tty_output
    end

    # Override the detected TTY output state (mostly for testing)
    def tty_output=( tty_output_state )
      @tty_output = tty_output_state
    end

    # We will truncate output if we are outputting to a TTY or if we've been
    # given an explicit column width to honor
    def truncate_output?
      tty_output? || @terminal_columns.nonzero?
    end

    # Display the tasks and comments.
    def display_tasks_and_comments
      displayable_tasks = tasks.select { |t|
        (options.show_all_tasks || t.comment) && t.name =~ options.show_task_pattern
      }
      case options.show_tasks
      when :tasks
        width = displayable_tasks.collect { |t| t.name_with_args.length }.max || 10
        max_column = truncate_output? ? terminal_width - name.size - width - 7 : nil

        displayable_tasks.each do |t|
          printf "#{name} %-#{width}s  # %s\n",
            t.name_with_args, max_column ? truncate(t.comment, max_column) : t.comment
        end
      when :describe
        displayable_tasks.each do |t|
          puts "#{name} #{t.name_with_args}"
          comment = t.full_comment || ""
          comment.split("\n").each do |line|
            puts "    #{line}"
          end
          puts
        end
      when :lines
        displayable_tasks.each do |t|
          t.locations.each do |loc|
            printf "#{name} %-30s %s\n",t.name_with_args, loc
          end
        end
      else
        fail "Unknown show task mode: '#{options.show_tasks}'"
      end
    end

    def terminal_width
      if @terminal_columns.nonzero?
        result = @terminal_columns
      else
        result = unix? ? dynamic_width : 80
      end
      (result < 10) ? 80 : result
    rescue
      80
    end

    # Calculate the dynamic width of the
    def dynamic_width
      @dynamic_width ||= (dynamic_width_stty.nonzero? || dynamic_width_tput)
    end

    def dynamic_width_stty
      %x{stty size 2>/dev/null}.split[1].to_i
    end

    def dynamic_width_tput
      %x{tput cols 2>/dev/null}.to_i
    end

    def unix?
      RbConfig::CONFIG['host_os'] =~ /(aix|darwin|linux|(net|free|open)bsd|cygwin|solaris|irix|hpux)/i
    end

    def windows?
      Win32.windows?
    end

    def truncate(string, width)
      if string.nil?
        ""
      elsif string.length <= width
        string
      else
        ( string[0, width-3] || "" ) + "..."
      end
    end

    # Display the tasks and prerequisites
    def display_prerequisites
      tasks.each do |t|
        puts "#{name} #{t.name}"
        t.prerequisites.each { |pre| puts "    #{pre}" }
      end
    end

    def trace(*str)
      options.trace_output ||= $stderr
      options.trace_output.puts(*str)
    end

    def sort_options(options)
      options.sort_by { |opt|
        opt.select { |o| o =~ /^-/ }.map { |o| o.downcase }.sort.reverse
      }
    end
    private :sort_options

    # A list of all the standard options used in rake, suitable for
    # passing to OptionParser.
    def standard_rake_options
      sort_options(
        [
          ['--all', '-A', "Show all tasks, even uncommented ones",
            lambda { |value|
              options.show_all_tasks = value
            }
          ],
          ['--backtrace [OUT]', "Enable full backtrace.  OUT can be stderr (default) or stdout.",
            lambda { |value|
              options.backtrace = true
              select_trace_output(options, 'backtrace', value)
            }
          ],
          ['--classic-namespace', '-C', "Put Task and FileTask in the top level namespace",
            lambda { |value|
              require 'rake/classic_namespace'
              options.classic_namespace = true
            }
          ],
          ['--comments', "Show commented tasks only",
            lambda { |value|
              options.show_all_tasks = !value
            }
          ],
          ['--describe', '-D [PATTERN]', "Describe the tasks (matching optional PATTERN), then exit.",
            lambda { |value|
              select_tasks_to_show(options, :describe, value)
            }
          ],
          ['--dry-run', '-n', "Do a dry run without executing actions.",
            lambda { |value|
              Rake.verbose(true)
              Rake.nowrite(true)
              options.dryrun = true
              options.trace = true
            }
          ],
          ['--execute',  '-e CODE', "Execute some Ruby code and exit.",
            lambda { |value|
              eval(value)
              exit
            }
          ],
          ['--execute-print',  '-p CODE', "Execute some Ruby code, print the result, then exit.",
            lambda { |value|
              puts eval(value)
              exit
            }
          ],
          ['--execute-continue',  '-E CODE',
            "Execute some Ruby code, then continue with normal task processing.",
            lambda { |value| eval(value) }
          ],
          ['--jobs',  '-j [NUMBER]',
            "Specifies the maximum number of tasks to execute in parallel. (default:2)",
            lambda { |value| options.thread_pool_size = [(value || 2).to_i,2].max }
          ],
          ['--job-stats [LEVEL]',
            "Display job statistics. LEVEL=history displays a complete job list",
            lambda { |value|
              if value =~ /^history/i
                options.job_stats = :history
              else
                options.job_stats = true
              end
            }
          ],
          ['--libdir', '-I LIBDIR', "Include LIBDIR in the search path for required modules.",
            lambda { |value| $:.push(value) }
          ],
          ['--multitask', '-m', "Treat all tasks as multitasks.",
            lambda { |value| options.always_multitask = true }
          ],
          ['--no-search', '--nosearch', '-N', "Do not search parent directories for the Rakefile.",
            lambda { |value| options.nosearch = true }
          ],
          ['--prereqs', '-P', "Display the tasks and dependencies, then exit.",
            lambda { |value| options.show_prereqs = true }
          ],
          ['--quiet', '-q', "Do not log messages to standard output.",
            lambda { |value| Rake.verbose(false) }
          ],
          ['--rakefile', '-f [FILE]', "Use FILE as the rakefile.",
            lambda { |value|
              value ||= ''
              @rakefiles.clear
              @rakefiles << value
            }
          ],
          ['--rakelibdir', '--rakelib', '-R RAKELIBDIR',
            "Auto-import any .rake files in RAKELIBDIR. (default is 'rakelib')",
            lambda { |value| options.rakelib = value.split(File::PATH_SEPARATOR) }
          ],
          ['--reduce-compat', "Remove DSL in Object; remove Module#const_missing which defines ::Task etc.",
            # Load-time option.
            # Handled in bin/rake where Rake::REDUCE_COMPAT is defined (or not).
            lambda { |_| }
          ],
          ['--require', '-r MODULE', "Require MODULE before executing rakefile.",
            lambda { |value|
              begin
                require value
              rescue LoadError => ex
                begin
                  rake_require value
                rescue LoadError
                  raise ex
                end
              end
            }
          ],
          ['--rules', "Trace the rules resolution.",
            lambda { |value| options.trace_rules = true }
          ],
          ['--silent', '-s', "Like --quiet, but also suppresses the 'in directory' announcement.",
            lambda { |value|
              Rake.verbose(false)
              options.silent = true
            }
          ],
          ['--suppress-backtrace PATTERN', "Suppress backtrace lines matching regexp PATTERN. Ignored if --trace is on.",
            lambda { |value|
              options.suppress_backtrace_pattern = Regexp.new(value)
            }
          ],
          ['--system',  '-g',
            "Using system wide (global) rakefiles (usually '~/.rake/*.rake').",
            lambda { |value| options.load_system = true }
          ],
          ['--no-system', '--nosystem', '-G',
            "Use standard project Rakefile search paths, ignore system wide rakefiles.",
            lambda { |value| options.ignore_system = true }
          ],
          ['--tasks', '-T [PATTERN]', "Display the tasks (matching optional PATTERN) with descriptions, then exit.",
            lambda { |value|
              select_tasks_to_show(options, :tasks, value)
            }
          ],
          ['--trace', '-t [OUT]', "Turn on invoke/execute tracing, enable full backtrace. OUT can be stderr (default) or stdout.",
            lambda { |value|
              options.trace = true
              options.backtrace = true
              select_trace_output(options, 'trace', value)
              Rake.verbose(true)
            }
          ],
          ['--verbose', '-v', "Log message to standard output.",
            lambda { |value| Rake.verbose(true) }
          ],
          ['--version', '-V', "Display the program version.",
            lambda { |value|
              puts "rake, version #{RAKEVERSION}"
              exit
            }
          ],
          ['--where', '-W [PATTERN]', "Describe the tasks (matching optional PATTERN), then exit.",
            lambda { |value|
              select_tasks_to_show(options, :lines, value)
              options.show_all_tasks = true
            }
          ],
          ['--no-deprecation-warnings', '-X', "Disable the deprecation warnings.",
            lambda { |value|
              options.ignore_deprecate = true
            }
          ],
        ])
    end

    def select_tasks_to_show(options, show_tasks, value)
      options.show_tasks = show_tasks
      options.show_task_pattern = Regexp.new(value || '')
      Rake::TaskManager.record_task_metadata = true
    end
    private :select_tasks_to_show

    def select_trace_output(options, trace_option, value)
      value = value.strip unless value.nil?
      case value
      when 'stdout'
        options.trace_output = $stdout
      when 'stderr', nil
        options.trace_output = $stderr
      else
        fail CommandLineOptionError, "Unrecognized --#{trace_option} option '#{value}'"
      end
    end
    private :select_trace_output

    # Read and handle the command line options.
    def handle_options
      options.rakelib = ['rakelib']
      options.trace_output = $stderr

      OptionParser.new do |opts|
        opts.banner = "rake [-f rakefile] {options} targets..."
        opts.separator ""
        opts.separator "Options are ..."

        opts.on_tail("-h", "--help", "-H", "Display this help message.") do
          puts opts
          exit
        end

        standard_rake_options.each { |args| opts.on(*args) }
        opts.environment('RAKEOPT')
      end.parse!

      # If class namespaces are requested, set the global options
      # according to the values in the options structure.
      if options.classic_namespace
        $show_tasks = options.show_tasks
        $show_prereqs = options.show_prereqs
        $trace = options.trace
        $dryrun = options.dryrun
        $silent = options.silent
      end
    end

    # Similar to the regular Ruby +require+ command, but will check
    # for *.rake files in addition to *.rb files.
    def rake_require(file_name, paths=$LOAD_PATH, loaded=$")
      fn = file_name + ".rake"
      return false if loaded.include?(fn)
      paths.each do |path|
        full_path = File.join(path, fn)
        if File.exist?(full_path)
          Rake.load_rakefile(full_path)
          loaded << fn
          return true
        end
      end
      fail LoadError, "Can't find #{file_name}"
    end

    def find_rakefile_location
      here = Dir.pwd
      while ! (fn = have_rakefile)
        Dir.chdir("..")
        if Dir.pwd == here || options.nosearch
          return nil
        end
        here = Dir.pwd
      end
      [fn, here]
    ensure
      Dir.chdir(Rake.original_dir)
    end

    def print_rakefile_directory(location)
      $stderr.puts "(in #{Dir.pwd})" unless
        options.silent or original_dir == location
    end

    def raw_load_rakefile # :nodoc:
      rakefile, location = find_rakefile_location
      if (! options.ignore_system) &&
          (options.load_system || rakefile.nil?) &&
          system_dir && File.directory?(system_dir)
        print_rakefile_directory(location)
        glob("#{system_dir}/*.rake") do |name|
          add_import name
        end
      else
        fail "No Rakefile found (looking for: #{@rakefiles.join(', ')})" if
          rakefile.nil?
        @rakefile = rakefile
        Dir.chdir(location)
        print_rakefile_directory(location)
        $rakefile = @rakefile if options.classic_namespace
        Rake.load_rakefile(File.expand_path(@rakefile)) if @rakefile && @rakefile != ''
        options.rakelib.each do |rlib|
          glob("#{rlib}/*.rake") do |name|
            add_import name
          end
        end
      end
      load_imports
    end

    def glob(path, &block)
      Rake.glob(path.gsub("\\", '/')).each(&block)
    end
    private :glob

    # The directory path containing the system wide rakefiles.
    def system_dir
      @system_dir ||=
        begin
          if ENV['RAKE_SYSTEM']
            ENV['RAKE_SYSTEM']
          else
            standard_system_dir
          end
        end
    end

    # The standard directory containing system wide rake files.
    if Win32.windows?
      def standard_system_dir #:nodoc:
        Win32.win32_system_dir
      end
    else
      def standard_system_dir #:nodoc:
        File.join(File.expand_path('~'), '.rake')
      end
    end
    private :standard_system_dir

    # Collect the list of tasks on the command line.  If no tasks are
    # given, return a list containing only the default task.
    # Environmental assignments are processed at this time as well.
    def collect_tasks
      @top_level_tasks = []
      ARGV.each do |arg|
        if arg =~ /^(\w+)=(.*)$/
          ENV[$1] = $2
        else
          @top_level_tasks << arg unless arg =~ /^-/
        end
      end
      @top_level_tasks.push("default") if @top_level_tasks.size == 0
    end

    # Add a file to the list of files to be imported.
    def add_import(fn)
      @pending_imports << fn
    end

    # Load the pending list of imported files.
    def load_imports
      while fn = @pending_imports.shift
        next if @imported.member?(fn)
        if fn_task = lookup(fn)
          fn_task.invoke
        end
        ext = File.extname(fn)
        loader = @loaders[ext] || @default_loader
        loader.load(fn)
        @imported << fn
      end
    end

    # Warn about deprecated use of top level constant names.
    def const_warning(const_name)
      @const_warning ||= false
      if ! @const_warning
        $stderr.puts %{WARNING: Deprecated reference to top-level constant '#{const_name}' } +
          %{found at: #{rakefile_location}} # '
        $stderr.puts %{    Use --classic-namespace on rake command}
        $stderr.puts %{    or 'require "rake/classic_namespace"' in Rakefile}
      end
      @const_warning = true
    end

    def rakefile_location(backtrace=caller)
      backtrace.map { |t| t[/([^:]+):/,1] }

      re = /^#{@rakefile}$/
      re = /#{re.source}/i if windows?

      backtrace.find { |str| str =~ re } || ''
    end

  private
    FIXNUM_MAX = (2**(0.size * 8 - 2) - 1) # :nodoc:

  end
end
