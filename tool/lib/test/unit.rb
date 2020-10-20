# frozen_string_literal: true
begin
  gem 'minitest', '< 5.0.0' if defined? Gem
rescue Gem::LoadError
end
require 'minitest/unit'
require 'test/unit/assertions'
require_relative '../envutil'
require_relative '../colorize'
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
        @run_options = orig_args

        if seed = options[:seed]
          srand(seed)
        else
          seed = options[:seed] = srand % 100_000
          srand(seed)
          orig_args.unshift "--seed=#{seed}"
        end

        @help = "\n" + orig_args.map { |s|
          "  " + (s =~ /[\s|&<>$()]/ ? s.inspect : s)
        }.join("\n")
        @options = options
      end

      private
      def setup_options(opts, options)
        opts.separator 'minitest options:'
        opts.version = MiniTest::Unit::VERSION

        opts.on '-h', '--help', 'Display this help.' do
          puts opts
          exit
        end

        opts.on '-s', '--seed SEED', Integer, "Sets random seed" do |m|
          options[:seed] = m.to_i
        end

        opts.on '-v', '--verbose', "Verbose. Show progress processing files." do
          options[:verbose] = true
          self.verbose = options[:verbose]
        end

        opts.on '-n', '--name PATTERN', "Filter test method names on pattern: /REGEXP/, !/REGEXP/ or STRING" do |a|
          (options[:filter] ||= []) << a
        end

        opts.on '--test-order=random|alpha|sorted|nosort', [:random, :alpha, :sorted, :nosort] do |a|
          MiniTest::Unit::TestCase.test_order = a
        end
      end

      def non_options(files, options)
        filter = options[:filter]
        if filter
          pos_pat = /\A\/(.*)\/\z/
          neg_pat = /\A!\/(.*)\/\z/
          negative, positive = filter.partition {|s| neg_pat =~ s}
          if positive.empty?
            filter = nil
          elsif negative.empty? and positive.size == 1 and pos_pat !~ positive[0]
            filter = positive[0]
          else
            filter = Regexp.union(*positive.map! {|s| Regexp.new(s[pos_pat, 1] || "\\A#{Regexp.quote(s)}\\z")})
          end
          unless negative.empty?
            negative = Regexp.union(*negative.map! {|s| Regexp.new(s[neg_pat, 1])})
            filter = /\A(?=.*#{filter})(?!.*#{negative})/
          end
          if Regexp === filter
            filter = filter.dup
            # bypass conversion in minitest
            def filter.=~(other)    # :nodoc:
              super unless Regexp === other
            end
          end
          options[:filter] = filter
        end
        true
      end
    end

    module Parallel # :nodoc: all
      def process_args(args = [])
        return @options if @options
        options = super
        if @options[:parallel]
          @files = args
        end
        options
      end

      def non_options(files, options)
        @jobserver = nil
        makeflags = ENV.delete("MAKEFLAGS")
        if !options[:parallel] and
          /(?:\A|\s)--jobserver-(?:auth|fds)=(\d+),(\d+)/ =~ makeflags
          begin
            r = IO.for_fd($1.to_i(10), "rb", autoclose: false)
            w = IO.for_fd($2.to_i(10), "wb", autoclose: false)
          rescue
            r.close if r
            nil
          else
            r.close_on_exec = true
            w.close_on_exec = true
            @jobserver = [r, w]
            options[:parallel] ||= 1
          end
        end
        super
      end

      def status(*args)
        result = super
        raise @interrupt if @interrupt
        result
      end

      private
      def setup_options(opts, options)
        super

        opts.separator "parallel test options:"

        options[:retry] = true

        opts.on '-j N', '--jobs N', /\A(t)?(\d+)\z/, "Allow run tests with N jobs at once" do |_, t, a|
          options[:testing] = true & t # For testing
          options[:parallel] = a.to_i
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

        opts.on '--ruby VAL', "Path to ruby which is used at -j option" do |a|
          options[:ruby] = a.split(/ /).reject(&:empty?)
        end
      end

      class Worker
        def self.launch(ruby,args=[])
          scale = EnvUtil.timeout_scale
          io = IO.popen([*ruby, "-W1",
                        "#{File.dirname(__FILE__)}/unit/parallel.rb",
                        *("--timeout-scale=#{scale}" if scale),
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
            raise unless /stream closed|closed stream/ =~ $!.message
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
        rescue Errno::EPIPE => e
          warn "#{@pid}:#{@status.to_s.ljust(7)}:#{@file}: #{e.message}"
        end

        def kill
          Process.kill(:KILL, @pid)
        rescue Errno::ESRCH
        end

        def died(*additional)
          @status = :quit
          @io.close
          status = $?
          if status and status.signaled?
            additional[0] ||= SignalException.new(status.termsig)
          end

          call_hook(:dead,*additional)
        end

        def to_s
          if @file and @status != :ready
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

      def flush_job_tokens
        if @jobserver
          r, w = @jobserver.shift(2)
          @jobserver = nil
          w << @job_tokens.slice!(0..-1)
          r.close
          w.close
        end
      end

      def after_worker_down(worker, e=nil, c=false)
        return unless @options[:parallel]
        return if @interrupt
        flush_job_tokens
        warn e if e
        real_file = worker.real_file and warn "running file: #{real_file}"
        @need_quit = true
        warn ""
        warn "Some worker was crashed. It seems ruby interpreter's bug"
        warn "or, a bug of test/unit/parallel.rb. try again without -j"
        warn "option."
        warn ""
        STDERR.flush
        exit c
      end

      def after_worker_quit(worker)
        return unless @options[:parallel]
        return if @interrupt
        worker.close
        if @jobserver and (token = @job_tokens.slice!(0))
          @jobserver[1] << token
        end
        @workers.delete(worker)
        @dead_workers << worker
        @ios = @workers.map(&:io)
      end

      def launch_worker
        begin
          worker = Worker.launch(@options[:ruby], @run_options)
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
            Timeout.timeout(1) do
              worker.quit
            end
          rescue Errno::EPIPE
          rescue Timeout::Error
          end
          worker.close
        end

        return if @workers.empty?
        begin
          Timeout.timeout(0.2 * @workers.size) do
            Process.waitall
          end
        rescue Timeout::Error
          @workers.each do |worker|
            worker.kill
          end
          @worker.clear
        end
      end

      FakeClass = Struct.new(:name)
      def fake_class(name)
        (@fake_classes ||= {})[name] ||= FakeClass.new(name)
      end

      def deal(io, type, result, rep, shutting_down = false)
        worker = @workers_hash[io]
        cmd = worker.read
        cmd.sub!(/\A\.+/, '') if cmd # read may return nil
        case cmd
        when ''
          # just only dots, ignore
        when /^okay$/
          worker.status = :running
        when /^ready(!)?$/
          bang = $1
          worker.status = :ready

          unless task = @tasks.shift
            worker.quit
            return nil
          end
          if @options[:separate] and not bang
            worker.quit
            worker = launch_worker
          end
          worker.run(task, type)
          @test_count += 1

          jobs_status(worker)
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
          jobs_status(worker) if @options[:job_status] == :replace
          return true
        when /^record (.+?)$/
          begin
            r = Marshal.load($1.unpack("m")[0])
          rescue => e
            print "unknown record: #{e.message} #{$1.unpack("m")[0].dump}"
            return true
          end
          record(fake_class(r[0]), *r[1..-1])
        when /^p (.+?)$/
          del_jobs_status
          print $1.unpack("m")[0]
          jobs_status(worker) if @options[:job_status] == :replace
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

        # Require needed thing for parallel running
        require 'timeout'
        @tasks = @files.dup # Array of filenames.

        case MiniTest::Unit::TestCase.test_order
        when :random
          @tasks.shuffle!
        else
          # sorted
        end

        @need_quit = false
        @dead_workers = []  # Array of dead workers.
        @warnings = []
        @total_tests = @tasks.size.to_s(10)
        rep = [] # FIXME: more good naming

        @workers      = [] # Array of workers.
        @workers_hash = {} # out-IO => worker
        @ios          = [] # Array of worker IOs
        @job_tokens   = String.new(encoding: Encoding::ASCII_8BIT) if @jobserver
        begin
          [@tasks.size, @options[:parallel]].min.times {launch_worker}

          while _io = IO.select(@ios)[0]
            break if _io.any? do |io|
              @need_quit or
                (deal(io, type, result, rep).nil? and
                 !@workers.any? {|x| [:running, :prepare].include? x.status})
            end
            if @jobserver and @job_tokens and !@tasks.empty? and !@workers.any? {|x| x.status == :ready}
              t = @jobserver[0].read_nonblock([@tasks.size, @options[:parallel]].min, exception: false)
              if String === t
                @job_tokens << t
                t.size.times {launch_worker}
              end
            end
          end
        rescue Interrupt => ex
          @interrupt = ex
          return result
        ensure
          if @interrupt
            @ios.select!{|x| @workers_hash[x].status == :running }
            while !@ios.empty? && (__io = IO.select(@ios,[],[],10))
              __io[0].reject! {|io| deal(io, type, result, rep, true)}
            end
          end

          quit_workers
          flush_job_tokens

          unless @interrupt || !@options[:retry] || @need_quit
            parallel = @options[:parallel]
            @options[:parallel] = false
            suites, rep = rep.partition {|r| r[:testcase] && r[:file] && r[:report].any? {|e| !e[2].is_a?(MiniTest::Skip)}}
            suites.map {|r| File.realpath(r[:file])}.uniq.each {|file| require file}
            suites.map! {|r| eval("::"+r[:testcase])}
            del_status_line or puts
            unless suites.empty?
              puts "\n""Retrying..."
              _run_suites(suites, type)
            end
            @options[:parallel] = parallel
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
        del_status_line
        result
      end
    end

    module Skipping # :nodoc: all
      def failed(s)
        super if !s or @options[:hide_skip]
      end

      private
      def setup_options(opts, options)
        super

        opts.separator "skipping options:"

        options[:hide_skip] = true

        opts.on '-q', '--hide-skip', 'Hide skipped tests' do
          options[:hide_skip] = true
        end

        opts.on '--show-skip', 'Show skipped tests' do
          options[:hide_skip] = false
        end
      end

      def _run_suites(suites, type)
        result = super
        report.reject!{|r| r.start_with? "Skipped:" } if @options[:hide_skip]
        report.sort_by!{|r| r.start_with?("Skipped:") ? 0 : \
                           (r.start_with?("Failure:") ? 1 : 2) }
        failed(nil)
        result
      end
    end

    module Statistics
      def update_list(list, rec, max)
        if i = list.empty? ? 0 : list.bsearch_index {|*a| yield(*a)}
          list[i, 0] = [rec]
          list[max..-1] = [] if list.size >= max
        end
      end

      def record(suite, method, assertions, time, error)
        if @options.values_at(:longest, :most_asserted).any?
          @tops ||= {}
          rec = [suite.name, method, assertions, time, error]
          if max = @options[:longest]
            update_list(@tops[:longest] ||= [], rec, max) {|_,_,_,t,_|t<time}
          end
          if max = @options[:most_asserted]
            update_list(@tops[:most_asserted] ||= [], rec, max) {|_,_,a,_,_|a<assertions}
          end
        end
        # (((@record ||= {})[suite] ||= {})[method]) = [assertions, time, error]
        super
      end

      def run(*args)
        result = super
        if @tops ||= nil
          @tops.each do |t, list|
            if list
              puts "#{t.to_s.tr('_', ' ')} tests:"
              list.each {|suite, method, assertions, time, error|
                printf "%5.2fsec(%d): %s#%s\n", time, assertions, suite, method
              }
            end
          end
        end
        result
      end

      private
      def setup_options(opts, options)
        super
        opts.separator "statistics options:"
        opts.on '--longest=N', Integer, 'Show longest N tests' do |n|
          options[:longest] = n
        end
        opts.on '--most-asserted=N', Integer, 'Show most asserted N tests' do |n|
          options[:most_asserted] = n
        end
      end
    end

    module StatusLine # :nodoc: all
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

      def del_status_line(flush = true)
        @status_line_size ||= 0
        if @options[:job_status] == :replace
          $stdout.print "\r"+" "*@status_line_size+"\r"
        else
          $stdout.puts if @status_line_size > 0
        end
        $stdout.flush if flush
        @status_line_size = 0
      end

      def add_status(line)
        @status_line_size ||= 0
        if @options[:job_status] == :replace
          line = line[0...(terminal_width-@status_line_size)]
        end
        print line
        @status_line_size += line.size
      end

      def jobs_status(worker)
        return if !@options[:job_status] or @options[:verbose]
        if @options[:job_status] == :replace
          status_line = @workers.map(&:to_s).join(" ")
        else
          status_line = worker.to_s
        end
        update_status(status_line) or (puts; nil)
      end

      def del_jobs_status
        return unless @options[:job_status] == :replace && @status_line_size.nonzero?
        del_status_line
      end

      def output
        (@output ||= nil) || super
      end

      def _prepare_run(suites, type)
        options[:job_status] ||= :replace if @tty && !@verbose
        case options[:color]
        when :always
          color = true
        when :auto, nil
          color = true if @tty || @options[:job_status] == :replace
        else
          color = false
        end
        @colorize = Colorize.new(color, colors_file: File.join(__dir__, "../../colors"))
        if color or @options[:job_status] == :replace
          @verbose = !options[:parallel]
        end
        @output = Output.new(self) unless @options[:testing]
        filter = options[:filter]
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
        del_status_line(false)
        add_status(@colorize.pass("[#{count}/#{@total_tests}]"))
        add_status(" #{s}")
        $stdout.print "\r" if @options[:job_status] == :replace and !@verbose
        $stdout.flush
      end

      def _print(s); $stdout.print(s); end
      def succeed; del_status_line; end

      def failed(s)
        return if s and @options[:job_status] != :replace
        sep = "\n"
        @report_count ||= 0
        report.each do |msg|
          if msg.start_with? "Skipped:"
            if @options[:hide_skip]
              del_status_line
              next
            end
            color = :skip
          else
            color = :fail
          end
          first, msg = msg.split(/$/, 2)
          first = sprintf("%3d) %s", @report_count += 1, first)
          $stdout.print(sep, @colorize.decorate(first, color), msg, "\n")
          sep = nil
        end
        report.clear
      end

      def initialize
        super
        @tty = $stdout.tty?
      end

      def run(*args)
        result = super
        puts "\nruby -v: #{RUBY_DESCRIPTION}"
        result
      end

      private
      def setup_options(opts, options)
        super

        opts.separator "status line options:"

        options[:job_status] = nil

        opts.on '--jobs-status [TYPE]', [:normal, :replace, :none],
                "Show status of jobs every file; Disabled when --jobs isn't specified." do |type|
          options[:job_status] = (type || :normal if type != :none)
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

      class Output < Struct.new(:runner) # :nodoc: all
        def puts(*a) $stdout.puts(*a) unless a.empty? end
        def respond_to_missing?(*a) $stdout.respond_to?(*a) end
        def method_missing(*a, &b) $stdout.__send__(*a, &b) end

        def print(s)
          case s
          when /\A(.*\#.*) = \z/
            runner.new_test($1)
          when /\A(.* s) = \z/
            runner.add_status(" = #$1")
          when /\A\.+\z/
            runner.succeed
          when /\A[EFS]\z/
            runner.failed(s)
          else
            $stdout.print(s)
          end
        end
      end
    end

    module LoadPathOption # :nodoc: all
      def non_options(files, options)
        begin
          require "rbconfig"
        rescue LoadError
          warn "#{caller(1, 1)[0]}: warning: Parallel running disabled because can't get path to ruby; run specify with --ruby argument"
          options[:parallel] = nil
        else
          options[:ruby] ||= [RbConfig.ruby]
        end

        super
      end

      def setup_options(parser, options)
        super
        parser.separator "load path options:"
        parser.on '-Idirectory', 'Add library load path' do |dirs|
          dirs.split(':').each { |d| $LOAD_PATH.unshift d }
        end
      end
    end

    module GlobOption # :nodoc: all
      @@testfile_prefix = "test"
      @@testfile_suffix = "test"

      def setup_options(parser, options)
        super
        parser.separator "globbing options:"
        parser.on '-B', '--base-directory DIR', 'Base directory to glob.' do |dir|
          raise OptionParser::InvalidArgument, "not a directory: #{dir}" unless File.directory?(dir)
          options[:base_directory] = dir
        end
        parser.on '-x', '--exclude REGEXP', 'Exclude test files on pattern.' do |pattern|
          (options[:reject] ||= []) << pattern
        end
      end

      def complement_test_name f, orig_f
        basename = File.basename(f)

        if /\.rb\z/ !~ basename
          return File.join(File.dirname(f), basename+'.rb')
        elsif /\Atest_/ !~ basename
          return File.join(File.dirname(f), 'test_'+basename)
        end if f.end_with?(basename) # otherwise basename is dirname/

        raise ArgumentError, "file not found: #{orig_f}"
      end

      def non_options(files, options)
        paths = [options.delete(:base_directory), nil].uniq
        if reject = options.delete(:reject)
          reject_pat = Regexp.union(reject.map {|r| %r"#{r}"})
        end
        files.map! {|f|
          f = f.tr(File::ALT_SEPARATOR, File::SEPARATOR) if File::ALT_SEPARATOR
          orig_f = f
          while true
            ret = ((paths if /\A\.\.?(?:\z|\/)/ !~ f) || [nil]).any? do |prefix|
              if prefix
                path = f.empty? ? prefix : "#{prefix}/#{f}"
              else
                next if f.empty?
                path = f
              end
              if f.end_with?(File::SEPARATOR) or !f.include?(File::SEPARATOR) or File.directory?(path)
                match = (Dir["#{path}/**/#{@@testfile_prefix}_*.rb"] + Dir["#{path}/**/*_#{@@testfile_suffix}.rb"]).uniq
              else
                match = Dir[path]
              end
              if !match.empty?
                if reject
                  match.reject! {|n|
                    n = n[(prefix.length+1)..-1] if prefix
                    reject_pat =~ n
                  }
                end
                break match
              elsif !reject or reject_pat !~ f and File.exist? path
                break path
              end
            end
            if !ret
              f = complement_test_name(f, orig_f)
            else
              break ret
            end
          end
        }
        files.flatten!
        super(files, options)
      end
    end

    module GCOption # :nodoc: all
      def setup_options(parser, options)
        super
        parser.separator "GC options:"
        parser.on '--[no-]gc-stress', 'Set GC.stress as true' do |flag|
          options[:gc_stress] = flag
        end
        parser.on '--[no-]gc-compact', 'GC.compact every time' do |flag|
          options[:gc_compact] = flag
        end
      end

      def non_options(files, options)
        if options.delete(:gc_stress)
          MiniTest::Unit::TestCase.class_eval do
            oldrun = instance_method(:run)
            define_method(:run) do |runner|
              begin
                gc_stress, GC.stress = GC.stress, true
                oldrun.bind_call(self, runner)
              ensure
                GC.stress = gc_stress
              end
            end
          end
        end
        if options.delete(:gc_compact)
          MiniTest::Unit::TestCase.class_eval do
            oldrun = instance_method(:run)
            define_method(:run) do |runner|
              begin
                oldrun.bind_call(self, runner)
              ensure
                GC.compact
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

    module RepeatOption # :nodoc: all
      def setup_options(parser, options)
        super
        options[:repeat_count] = nil
        parser.separator "repeat options:"
        parser.on '--repeat-count=NUM', "Number of times to repeat", Integer do |n|
          options[:repeat_count] = n
        end
      end

      def _run_anything(type)
        @repeat_count = @options[:repeat_count]
        super
      end
    end

    module ExcludesOption # :nodoc: all
      class ExcludedMethods < Struct.new(:excludes)
        def exclude(name, reason)
          excludes[name] = reason
        end

        def exclude_from(klass)
          excludes = self.excludes
          pattern = excludes.keys.grep(Regexp).tap {|k|
            break (Regexp.new(k.join('|')) unless k.empty?)
          }
          klass.class_eval do
            public_instance_methods(false).each do |method|
              if excludes[method] or (pattern and pattern =~ method)
                remove_method(method)
              end
            end
            public_instance_methods(true).each do |method|
              if excludes[method] or (pattern and pattern =~ method)
                undef_method(method)
              end
            end
          end
        end

        def self.load(dirs, name)
          return unless dirs and name
          instance = nil
          dirs.each do |dir|
            path = File.join(dir, name.gsub(/::/, '/') + ".rb")
            begin
              src = File.read(path)
            rescue Errno::ENOENT
              nil
            else
              instance ||= new({})
              instance.instance_eval(src, path)
            end
          end
          instance
        end
      end

      def setup_options(parser, options)
        super
        if excludes = ENV["EXCLUDES"]
          excludes = excludes.split(File::PATH_SEPARATOR)
        end
        options[:excludes] = excludes || []
        parser.separator "excludes options:"
        parser.on '-X', '--excludes-dir DIRECTORY', "Directory name of exclude files" do |d|
          options[:excludes].concat d.split(File::PATH_SEPARATOR)
        end
      end

      def _run_suite(suite, type)
        if ex = ExcludedMethods.load(@options[:excludes], suite.name)
          ex.exclude_from(suite)
        end
        super
      end
    end

    module TimeoutOption
      def setup_options(parser, options)
        super
        parser.separator "timeout options:"
        parser.on '--timeout-scale NUM', '--subprocess-timeout-scale NUM', "Scale timeout", Float do |scale|
          raise OptionParser::InvalidArgument, "timeout scale must be positive" unless scale > 0
          options[:timeout_scale] = scale
        end
      end

      def non_options(files, options)
        if scale = options[:timeout_scale] or
          (scale = ENV["RUBY_TEST_TIMEOUT_SCALE"] || ENV["RUBY_TEST_SUBPROCESS_TIMEOUT_SCALE"] and
           (scale = scale.to_f) > 0)
          EnvUtil.timeout_scale = scale
        end
        super
      end
    end

    class Runner < MiniTest::Unit # :nodoc: all
      include Test::Unit::Options
      include Test::Unit::StatusLine
      include Test::Unit::Parallel
      include Test::Unit::Statistics
      include Test::Unit::Skipping
      include Test::Unit::GlobOption
      include Test::Unit::RepeatOption
      include Test::Unit::LoadPathOption
      include Test::Unit::GCOption
      include Test::Unit::ExcludesOption
      include Test::Unit::TimeoutOption
      include Test::Unit::RunCount

      def run(argv)
        super
      rescue NoMemoryError
        system("cat /proc/meminfo") if File.exist?("/proc/meminfo")
        system("ps x -opid,args,%cpu,%mem,nlwp,rss,vsz,wchan,stat,start,time,etime,blocked,caught,ignored,pending,f") if File.exist?("/bin/ps")
        raise
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

      alias mini_run_suite _run_suite

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
    end

    class AutoRunner # :nodoc: all
      class Runner < Test::Unit::Runner
        include Test::Unit::RequireFiles
      end

      attr_accessor :to_run, :options

      def initialize(force_standalone = false, default_dir = nil, argv = ARGV)
        @force_standalone = force_standalone
        @runner = Runner.new do |files, options|
          base = options[:base_directory] ||= default_dir
          files << default_dir if files.empty? and default_dir
          @to_run = files
          yield self if block_given?
          $LOAD_PATH.unshift base if base
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
  test_order = self.test_order
  class << self
    attr_writer :test_order
    undef test_order
  end
  def self.test_order
    defined?(@test_order) ? @test_order : superclass.test_order
  end
  self.test_order = test_order
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
