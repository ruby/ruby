begin
  gem 'minitest', '< 5.0.0' if defined? Gem
rescue Gem::LoadError
end
require 'minitest/unit'
require 'test/unit/assertions'
require_relative '../envutil'
require 'test/unit/testcase'
require 'optparse'

# See Test::Unit
module Test
  ##
  # Test::Unit is an implementation of the xUnit testing framework for Ruby.
  #
  # If you are writing new test code, please use MiniTest instead of Test::Unit.
  #
  # Test::Unit has been left in the standard library to support legacy test
  # suites.
  module Unit
    TEST_UNIT_IMPLEMENTATION = 'test/unit compatibility layer using minitest' # :nodoc:

    module RunCount # :nodoc: all
      @@run_count = 0

      def self.have_run?
        @@run_count.nonzero?
      end

      def run(*)
        @@run_count += 1
        super
      end

      def run_once
        return if have_run?
        return if $! # don't run if there was an exception
        yield
      end
      module_function :run_once
    end

    module Options # :nodoc: all
      def initialize(*, &block)
        @init_hook = block
        @options = nil
        super(&nil)
      end

      def option_parser
        @option_parser ||= OptionParser.new
      end

      def process_args(args = [])
        return @options if @options
        orig_args = args.dup
        options = {}
        opts = option_parser
        setup_options(opts, options)
        opts.parse!(args)
        orig_args -= args
        args = @init_hook.call(args, options) if @init_hook
        non_options(args, options)
        @help = orig_args.map { |s| s =~ /[\s|&<>$()]/ ? s.inspect : s }.join " "
        @options = options
        if @options[:parallel]
          @files = args
          @args = orig_args
        end
        options
      end

      private
      def setup_options(opts, options)
        opts.separator 'minitest options:'
        opts.version = MiniTest::Unit::VERSION

        options[:retry] = true
        options[:job_status] = nil
        options[:hide_skip] = true

        opts.on '-h', '--help', 'Display this help.' do
          puts opts
          exit
        end

        opts.on '-s', '--seed SEED', Integer, "Sets random seed" do |m|
          options[:seed] = m
        end

        opts.on '-v', '--verbose', "Verbose. Show progress processing files." do
          options[:verbose] = true
          self.verbose = options[:verbose]
        end

        opts.on '-n', '--name PATTERN', "Filter test names on pattern." do |a|
          options[:filter] = a
        end

        opts.on '--jobs-status [TYPE]', [:normal, :replace],
                "Show status of jobs every file; Disabled when --jobs isn't specified." do |type|
          options[:job_status] = type || :normal
        end

        opts.on '-j N', '--jobs N', "Allow run tests with N jobs at once" do |a|
          if /^t/ =~ a
            options[:testing] = true # For testing
            options[:parallel] = a[1..-1].to_i
          else
            options[:parallel] = a.to_i
          end
        end

        opts.on '--separate', "Restart job process after one testcase has done" do
          options[:parallel] ||= 1
          options[:separate] = true
        end

        opts.on '--retry', "Retry running testcase when --jobs specified" do
          options[:retry] = true
        end

        opts.on '--no-retry', "Disable --retry" do
          options[:retry] = false
        end

        opts.on '--ruby VAL', "Path to ruby; It'll have used at -j option" do |a|
          options[:ruby] = a.split(/ /).reject(&:empty?)
        end

        opts.on '-q', '--hide-skip', 'Hide skipped tests' do
          options[:hide_skip] = true
        end

        opts.on '--show-skip', 'Show skipped tests' do
          options[:hide_skip] = false
        end

        opts.on '--color[=WHEN]',
                [:always, :never, :auto],
                "colorize the output.  WHEN defaults to 'always'", "or can be 'never' or 'auto'." do |c|
          options[:color] = c || :always
        end

        opts.on '--tty[=WHEN]',
                [:yes, :no],
                "force to output tty control.  WHEN defaults to 'yes'", "or can be 'no'." do |c|
          @tty = c != :no
        end
      end

      def non_options(files, options)
        begin
          require "rbconfig"
        rescue LoadError
          warn "#{caller(1)[0]}: warning: Parallel running disabled because can't get path to ruby; run specify with --ruby argument"
          options[:parallel] = nil
        else
          options[:ruby] ||= [RbConfig.ruby]
        end

        true
      end
    end

    module GlobOption # :nodoc: all
      @@testfile_prefix = "test"

      def setup_options(parser, options)
        super
        parser.on '-b', '--basedir=DIR', 'Base directory of test suites.' do |dir|
          options[:base_directory] = dir
        end
        parser.on '-x', '--exclude PATTERN', 'Exclude test files on pattern.' do |pattern|
          (options[:reject] ||= []) << pattern
        end
      end

      def non_options(files, options)
        paths = [options.delete(:base_directory), nil].uniq
        if reject = options.delete(:reject)
          reject_pat = Regexp.union(reject.map {|r| /#{r}/ })
        end
        files.map! {|f|
          f = f.tr(File::ALT_SEPARATOR, File::SEPARATOR) if File::ALT_SEPARATOR
          ((paths if /\A\.\.?(?:\z|\/)/ !~ f) || [nil]).any? do |prefix|
            if prefix
              path = f.empty? ? prefix : "#{prefix}/#{f}"
            else
              next if f.empty?
              path = f
            end
            if !(match = Dir["#{path}/**/#{@@testfile_prefix}_*.rb"]).empty?
              if reject
                match.reject! {|n|
                  n[(prefix.length+1)..-1] if prefix
                  reject_pat =~ n
                }
              end
              break match
            elsif !reject or reject_pat !~ f and File.exist? path
              break path
            end
          end or
            raise ArgumentError, "file not found: #{f}"
        }
        files.flatten!
        super(files, options)
      end
    end

    module LoadPathOption # :nodoc: all
      def setup_options(parser, options)
        super
        parser.on '-Idirectory', 'Add library load path' do |dirs|
          dirs.split(':').each { |d| $LOAD_PATH.unshift d }
        end
      end
    end

    module GCStressOption # :nodoc: all
      def setup_options(parser, options)
        super
        parser.on '--[no-]gc-stress', 'Set GC.stress as true' do |flag|
          options[:gc_stress] = flag
        end
      end

      def non_options(files, options)
        if options.delete(:gc_stress)
          MiniTest::Unit::TestCase.class_eval do
            oldrun = instance_method(:run)
            define_method(:run) do |runner|
              begin
                gc_stress, GC.stress = GC.stress, true
                oldrun.bind(self).call(runner)
              ensure
                GC.stress = gc_stress
              end
            end
          end
        end
        super
      end
    end

    module RequireFiles # :nodoc: all
      def non_options(files, options)
        return false if !super
        errors = {}
        result = false
        files.each {|f|
          d = File.dirname(path = File.realpath(f))
          unless $:.include? d
            $: << d
          end
          begin
            require path unless options[:parallel]
            result = true
          rescue LoadError
            next if errors[$!.message]
            errors[$!.message] = true
            puts "#{f}: #{$!}"
          end
        }
        result
      end
    end

    class Runner < MiniTest::Unit # :nodoc: all
      include Test::Unit::Options
      include Test::Unit::GlobOption
      include Test::Unit::LoadPathOption
      include Test::Unit::GCStressOption
      include Test::Unit::RunCount

      class Worker
        def self.launch(ruby,args=[])
          io = IO.popen([*ruby,
                        "#{File.dirname(__FILE__)}/unit/parallel.rb",
                        *args], "rb+")
          new(io, io.pid, :waiting)
        end

        attr_reader :quit_called

        def initialize(io, pid, status)
          @io = io
          @pid = pid
          @status = status
          @file = nil
          @real_file = nil
          @loadpath = []
          @hooks = {}
          @quit_called = false
        end

        def puts(*args)
          @io.puts(*args)
        end

        def run(task,type)
          @file = File.basename(task, ".rb")
          @real_file = task
          begin
            puts "loadpath #{[Marshal.dump($:-@loadpath)].pack("m0")}"
            @loadpath = $:.dup
            puts "run #{task} #{type}"
            @status = :prepare
          rescue Errno::EPIPE
            died
          rescue IOError
            raise unless ["stream closed","closed stream"].include? $!.message
            died
          end
        end

        def hook(id,&block)
          @hooks[id] ||= []
          @hooks[id] << block
          self
        end

        def read
          res = (@status == :quit) ? @io.read : @io.gets
          res && res.chomp
        end

        def close
          @io.close unless @io.closed?
          self
        rescue IOError
        end

        def quit
          return if @io.closed?
          @quit_called = true
          @io.puts "quit"
          @io.close
        end

        def kill
          Process.kill(:KILL, @pid)
        rescue Errno::ESRCH
        end

        def died(*additional)
          @status = :quit
          @io.close

          call_hook(:dead,*additional)
        end

        def to_s
          if @file
            "#{@pid}=#{@file}"
          else
            "#{@pid}:#{@status.to_s.ljust(7)}"
          end
        end

        attr_reader :io, :pid
        attr_accessor :status, :file, :real_file, :loadpath

        private

        def call_hook(id,*additional)
          @hooks[id] ||= []
          @hooks[id].each{|hook| hook[self,additional] }
          self
        end

      end

      class << self; undef autorun; end

      @@stop_auto_run = false
      def self.autorun
        at_exit {
          Test::Unit::RunCount.run_once {
            exit(Test::Unit::Runner.new.run(ARGV) || true)
          } unless @@stop_auto_run
        } unless @@installed_at_exit
        @@installed_at_exit = true
      end

      def after_worker_down(worker, e=nil, c=false)
        return unless @options[:parallel]
        return if @interrupt
        warn e if e
        @need_quit = true
        warn ""
        warn "Some worker was crashed. It seems ruby interpreter's bug"
        warn "or, a bug of test/unit/parallel.rb. try again without -j"
        warn "option."
        warn ""
        STDERR.flush
        exit c
      end

      def terminal_width
        unless @terminal_width ||= nil
          begin
            require 'io/console'
            width = $stdout.winsize[1]
          rescue LoadError, NoMethodError, Errno::ENOTTY, Errno::EBADF, Errno::EINVAL
            width = ENV["COLUMNS"].to_i.nonzero? || 80
          end
          width -= 1 if /mswin|mingw/ =~ RUBY_PLATFORM
          @terminal_width = width
        end
        @terminal_width
      end

      def del_status_line
        @status_line_size ||= 0
        unless @options[:job_status] == :replace
          $stdout.puts
          return
        end
        print "\r"+" "*@status_line_size+"\r"
        $stdout.flush
        @status_line_size = 0
      end

      def put_status(line)
        unless @options[:job_status] == :replace
          print(line)
          return
        end
        @status_line_size ||= 0
        del_status_line
        $stdout.flush
        line = line[0...terminal_width]
        print line
        $stdout.flush
        @status_line_size = line.size
      end

      def add_status(line)
        unless @options[:job_status] == :replace
          print(line)
          return
        end
        @status_line_size ||= 0
        line = line[0...(terminal_width-@status_line_size)]
        print line
        $stdout.flush
        @status_line_size += line.size
      end

      def jobs_status
        return unless @options[:job_status]
        puts "" unless @options[:verbose] or @options[:job_status] == :replace
        status_line = @workers.map(&:to_s).join(" ")
        update_status(status_line) or (puts; nil)
      end

      def del_jobs_status
        return unless @options[:job_status] == :replace && @status_line_size.nonzero?
        del_status_line
      end

      def after_worker_quit(worker)
        return unless @options[:parallel]
        return if @interrupt
        @workers.delete(worker)
        @dead_workers << worker
        @ios = @workers.map(&:io)
      end

      def launch_worker
        begin
          worker = Worker.launch(@options[:ruby],@args)
        rescue => e
          abort "ERROR: Failed to launch job process - #{e.class}: #{e.message}"
        end
        worker.hook(:dead) do |w,info|
          after_worker_quit w
          after_worker_down w, *info if !info.empty? && !worker.quit_called
        end
        @workers << worker
        @ios << worker.io
        @workers_hash[worker.io] = worker
        worker
      end

      def delete_worker(worker)
        @workers_hash.delete worker.io
        @workers.delete worker
        @ios.delete worker.io
      end

      def quit_workers
        return if @workers.empty?
        @workers.reject! do |worker|
          begin
            timeout(1) do
              worker.quit
            end
          rescue Errno::EPIPE
          rescue Timeout::Error
          end
          worker.close
        end

        return if @workers.empty?
        begin
          timeout(0.2 * @workers.size) do
            Process.waitall
          end
        rescue Timeout::Error
          @workers.each do |worker|
            worker.kill
          end
          @worker.clear
        end
      end

      def start_watchdog
        Thread.new do
          while stat = Process.wait2
            break if @interrupt # Break when interrupt
            pid, stat = stat
            w = (@workers + @dead_workers).find{|x| pid == x.pid }
            next unless w
            w = w.dup
            if w.status != :quit && !w.quit_called?
              # Worker down
              w.died(nil, !stat.signaled? && stat.exitstatus)
            end
          end
        end
      end

      def deal(io, type, result, rep, shutting_down = false)
        worker = @workers_hash[io]
        cmd = worker.read
        cmd.sub!(/\A\.+/, '')
        case cmd
        when ''
          # just only dots, ignore
        when /^okay$/
          worker.status = :running
          jobs_status
        when /^ready(!)?$/
          bang = $1
          worker.status = :ready

          return nil unless task = @tasks.shift
          if @options[:separate] and not bang
            worker.quit
            worker = add_worker
          end
          worker.run(task, type)
          @test_count += 1

          jobs_status
        when /^done (.+?)$/
          begin
            r = Marshal.load($1.unpack("m")[0])
          rescue
            print "unknown object: #{$1.unpack("m")[0].dump}"
            return true
          end
          result << r[0..1] unless r[0..1] == [nil,nil]
          rep    << {file: worker.real_file, report: r[2], result: r[3], testcase: r[5]}
          $:.push(*r[4]).uniq!
          return true
        when /^p (.+?)$/
          del_jobs_status
          print $1.unpack("m")[0]
          jobs_status if @options[:job_status] == :replace
        when /^after (.+?)$/
          @warnings << Marshal.load($1.unpack("m")[0])
        when /^bye (.+?)$/
          after_worker_down worker, Marshal.load($1.unpack("m")[0])
        when /^bye$/, nil
          if shutting_down || worker.quit_called
            after_worker_quit worker
          else
            after_worker_down worker
          end
        else
          print "unknown command: #{cmd.dump}\n"
        end
        return false
      end

      def _run_parallel suites, type, result
        if @options[:parallel] < 1
          warn "Error: parameter of -j option should be greater than 0."
          return
        end

        # Require needed things for parallel running
        require 'thread'
        require 'timeout'
        @tasks = @files.dup # Array of filenames.
        @need_quit = false
        @dead_workers = []  # Array of dead workers.
        @warnings = []
        @total_tests = @tasks.size.to_s(10)
        rep = [] # FIXME: more good naming

        @workers      = [] # Array of workers.
        @workers_hash = {} # out-IO => worker
        @ios          = [] # Array of worker IOs
        begin
          # Thread: watchdog
          watchdog = start_watchdog

          @options[:parallel].times {launch_worker}

          while _io = IO.select(@ios)[0]
            break if _io.any? do |io|
              @need_quit or
                (deal(io, type, result, rep).nil? and
                 !@workers.any? {|x| [:running, :prepare].include? x.status})
            end
          end
        rescue Interrupt => ex
          @interrupt = ex
          return result
        ensure
          watchdog.kill if watchdog
          if @interrupt
            @ios.select!{|x| @workers_hash[x].status == :running }
            while !@ios.empty? && (__io = IO.select(@ios,[],[],10))
              __io[0].reject! {|io| deal(io, type, result, rep, true)}
            end
          end

          quit_workers

          unless @interrupt || !@options[:retry] || @need_quit
            @options[:parallel] = false
            suites, rep = rep.partition {|r| r[:testcase] && r[:file] && r[:report].any? {|e| !e[2].is_a?(MiniTest::Skip)}}
            suites.map {|r| r[:file]}.uniq.each {|file| require file}
            suites.map! {|r| eval("::"+r[:testcase])}
            del_status_line or puts
            unless suites.empty?
              puts "Retrying..."
              _run_suites(suites, type)
            end
          end
          unless @options[:retry]
            del_status_line or puts
          end
          unless rep.empty?
            rep.each do |r|
              r[:report].each do |f|
                puke(*f) if f
              end
            end
            if @options[:retry]
              @errors   += rep.map{|x| x[:result][0] }.inject(:+)
              @failures += rep.map{|x| x[:result][1] }.inject(:+)
              @skips    += rep.map{|x| x[:result][2] }.inject(:+)
            end
          end
          unless @warnings.empty?
            warn ""
            @warnings.uniq! {|w| w[1].message}
            @warnings.each do |w|
              warn "#{w[0]}: #{w[1].message} (#{w[1].class})"
            end
            warn ""
          end
        end
      end

      def _run_suites suites, type
        _prepare_run(suites, type)
        @interrupt = nil
        result = []
        GC.start
        if @options[:parallel]
          _run_parallel suites, type, result
        else
          suites.each {|suite|
            begin
              result << _run_suite(suite, type)
            rescue Interrupt => e
              @interrupt = e
              break
            end
          }
        end
        report.reject!{|r| r.start_with? "Skipped:" } if @options[:hide_skip]
        report.sort_by!{|r| r.start_with?("Skipped:") ? 0 : \
                           (r.start_with?("Failure:") ? 1 : 2) }
        result
      end

      alias mini_run_suite _run_suite

      def output
        (@output ||= nil) || super
      end

      def _prepare_run(suites, type)
        options[:job_status] ||= :replace if @tty && !@verbose
        case options[:color]
        when :always
          color = true
        when :auto, nil
          color = @options[:job_status] == :replace && /dumb/ !~ ENV["TERM"]
        else
          color = false
        end
        if color
          # dircolors-like style
          colors = (colors = ENV['TEST_COLORS']) ? Hash[colors.scan(/(\w+)=([^:]*)/)] : {}
          @passed_color = "\e[#{colors["pass"] || "32"}m"
          @failed_color = "\e[#{colors["fail"] || "31"}m"
          @skipped_color = "\e[#{colors["skip"] || "33"}m"
          @reset_color = "\e[m"
        else
          @passed_color = @failed_color = @skipped_color = @reset_color = ""
        end
        if color or @options[:job_status] == :replace
          @verbose = !options[:parallel]
          @output = StatusLineOutput.new(self)
        end
        if /\A\/(.*)\/\z/ =~ (filter = options[:filter])
          filter = Regexp.new($1)
        end
        type = "#{type}_methods"
        total = if filter
                  suites.inject(0) {|n, suite| n + suite.send(type).grep(filter).size}
                else
                  suites.inject(0) {|n, suite| n + suite.send(type).size}
                end
        @test_count = 0
        @total_tests = total.to_s(10)
      end

      def new_test(s)
        @test_count += 1
        update_status(s)
      end

      def update_status(s)
        count = @test_count.to_s(10).rjust(@total_tests.size)
        put_status("#{@passed_color}[#{count}/#{@total_tests}]#{@reset_color} #{s}")
      end

      def _print(s); $stdout.print(s); end
      def succeed; del_status_line; end

      def failed(s)
        sep = "\n"
        @report_count ||= 0
        report.each do |msg|
          if msg.start_with? "Skipped:"
            if @options[:hide_skip]
              del_status_line
              next
            end
            color = @skipped_color
          else
            color = @failed_color
          end
          msg = msg.split(/$/, 2)
          $stdout.printf("%s%s%3d) %s%s%s\n",
                         sep, color, @report_count += 1,
                         msg[0], @reset_color, msg[1])
          sep = nil
        end
        report.clear
      end

      # Overriding of MiniTest::Unit#puke
      def puke klass, meth, e
        # TODO:
        #   this overriding is for minitest feature that skip messages are
        #   hidden when not verbose (-v), note this is temporally.
        n = report.size
        rep = super
        if MiniTest::Skip === e and /no message given\z/ =~ e.message
          report.slice!(n..-1)
          rep = "."
        end
        rep
      end

      def initialize
        super
        @tty = $stdout.tty?
      end

      def status(*args)
        result = super
        raise @interrupt if @interrupt
        result
      end

      def run(*args)
        result = super
        puts "\nruby -v: #{RUBY_DESCRIPTION}"
        result
      end
    end

    class StatusLineOutput < Struct.new(:runner) # :nodoc: all
      def puts(*a) $stdout.puts(*a) unless a.empty? end
      def respond_to_missing?(*a) $stdout.respond_to?(*a) end
      def method_missing(*a, &b) $stdout.__send__(*a, &b) end

      def print(s)
        case s
        when /\A(.*\#.*) = \z/
          runner.new_test($1)
        when /\A(.* s) = \z/
          runner.add_status(" = "+$1.chomp)
        when /\A\.+\z/
          runner.succeed
        when /\A[EFS]\z/
          runner.failed(s)
        else
          $stdout.print(s)
        end
      end
    end

    class AutoRunner # :nodoc: all
      class Runner < Test::Unit::Runner
        include Test::Unit::RequireFiles
      end

      attr_accessor :to_run, :options

      def initialize(force_standalone = false, default_dir = nil, argv = ARGV)
        @force_standalone = force_standalone
        @runner = Runner.new do |files, options|
          options[:base_directory] ||= default_dir
          files << default_dir if files.empty? and default_dir
          @to_run = files
          yield self if block_given?
          files
        end
        Runner.runner = @runner
        @options = @runner.option_parser
        if @force_standalone
          @options.banner.sub!(/\[options\]/, '\& tests...')
        end
        @argv = argv
      end

      def process_args(*args)
        @runner.process_args(*args)
        !@to_run.empty?
      end

      def run
        if @force_standalone and not process_args(@argv)
          abort @options.banner
        end
        @runner.run(@argv) || true
      end

      def self.run(*args)
        new(*args).run
      end
    end

    class ProxyError < StandardError # :nodoc: all
      def initialize(ex)
        @message = ex.message
        @backtrace = ex.backtrace
      end

      attr_accessor :message, :backtrace
    end
  end
end

module MiniTest # :nodoc: all
  class Unit
  end
end

class MiniTest::Unit::TestCase # :nodoc: all
  undef run_test
  RUN_TEST_TRACE = "#{__FILE__}:#{__LINE__+3}:in `run_test'".freeze
  def run_test(name)
    progname, $0 = $0, "#{$0}: #{self.class}##{name}"
    self.__send__(name)
  ensure
    $@.delete(RUN_TEST_TRACE) if $@
    $0 = progname
  end
end

Test::Unit::Runner.autorun
