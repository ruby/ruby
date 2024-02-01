# frozen_string_literal: true

# Enable deprecation warnings for test-all, so deprecated methods/constants/functions are dealt with early.
Warning[:deprecated] = true

if ENV['BACKTRACE_FOR_DEPRECATION_WARNINGS']
  Warning.extend Module.new {
    def warn(message, category: nil, **kwargs)
      if category == :deprecated and $stderr.respond_to?(:puts)
        $stderr.puts nil, message, caller, nil
      else
        super
      end
    end
  }
end

require_relative '../envutil'
require_relative '../colorize'
require_relative '../leakchecker'
require_relative '../test/unit/testcase'
require 'optparse'

# See Test::Unit
module Test

  ##
  # Test::Unit is an implementation of the xUnit testing framework for Ruby.
  module Unit
    ##
    # Assertion base class

    class AssertionFailedError < Exception; end

    ##
    # Assertion raised when skipping a test

    class PendedError < AssertionFailedError; end

    module Order
      class NoSort
        def initialize(seed)
        end

        def sort_by_name(list)
          list
        end

        alias sort_by_string sort_by_name

        def group(list)
          list
        end
      end

      class Alpha < NoSort
        def sort_by_name(list)
          list.sort_by(&:name)
        end

        def sort_by_string(list)
          list.sort
        end

      end

      # shuffle test suites based on CRC32 of their names
      Shuffle = Struct.new(:seed, :salt) do
        def initialize(seed)
          self.class::CRC_TBL ||= (0..255).map {|i|
            (0..7).inject(i) {|c,| (c & 1 == 1) ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
          }.freeze

          salt = [seed].pack("V").unpack1("H*")
          super(seed, "\n#{salt}".freeze).freeze
        end

        def sort_by_name(list)
          list.sort_by {|e| randomize_key(e.name)}
        end

        def sort_by_string(list)
          list.sort_by {|e| randomize_key(e)}
        end

        def group(list)
          list
        end

        private

        def crc32(str, crc32 = 0xffffffff)
          crc_tbl = self.class::CRC_TBL
          str.each_byte do |data|
            crc32 = crc_tbl[(crc32 ^ data) & 0xff] ^ (crc32 >> 8)
          end
          crc32
        end

        def randomize_key(name)
          crc32(salt, crc32(name)) ^ 0xffffffff
        end
      end

      Types = {
        random: Shuffle,
        alpha: Alpha,
        sorted: Alpha,
        nosort: NoSort,
      }
      Types.default_proc = proc {|_, order|
        raise "Unknown test_order: #{order.inspect}"
      }
    end

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

        order = options[:test_order]
        if seed = options[:seed]
          order ||= :random
        elsif (order ||= :random) == :random
          seed = options[:seed] = rand(0x10000)
          orig_args.unshift "--seed=#{seed}"
        end
        Test::Unit::TestCase.test_order = order if order
        order = Test::Unit::TestCase.test_order
        @order = Test::Unit::Order::Types[order].new(seed)

        @help = "\n" + orig_args.map { |s|
          "  " + (s =~ /[\s|&<>$()]/ ? s.inspect : s)
        }.join("\n")

        @options = options
      end

      private
      def setup_options(opts, options)
        opts.separator 'test-unit options:'

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

        orders = Test::Unit::Order::Types.keys
        opts.on "--test-order=#{orders.join('|')}", orders do |a|
          options[:test_order] = a
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
            unless /\A[A-Z]\w*(?:::[A-Z]\w*)*#/ =~ filter
              filter = /##{Regexp.quote(filter)}\z/
            end
          else
            filter = Regexp.union(*positive.map! {|s| Regexp.new(s[pos_pat, 1] || "\\A#{Regexp.quote(s)}\\z")})
          end
          unless negative.empty?
            negative = Regexp.union(*negative.map! {|s| Regexp.new(s[neg_pat, 1])})
            filter = /\A(?=.*#{filter})(?!.*#{negative})/
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
          /(?:\A|\s)--jobserver-(?:auth|fds)=(?:(\d+),(\d+)|fifo:((?:\\.|\S)+))/ =~ makeflags
          begin
            if fifo = $3
              fifo.gsub!(/\\(?=.)/, '')
              r = File.open(fifo, IO::RDONLY|IO::NONBLOCK|IO::BINARY)
              w = File.open(fifo, IO::WRONLY|IO::NONBLOCK|IO::BINARY)
            else
              r = IO.for_fd($1.to_i(10), "rb", autoclose: false)
              w = IO.for_fd($2.to_i(10), "wb", autoclose: false)
            end
          rescue
            r.close if r
            nil
          else
            r.close_on_exec = true
            w.close_on_exec = true
            @jobserver = [r, w]
            options[:parallel] ||= 256 # number of tokens to acquire first
          end
        end
        @worker_timeout = EnvUtil.apply_timeout_scale(options[:worker_timeout] || 180)
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

        opts.on '--worker-timeout=N', Integer, "Timeout workers not responding in N seconds" do |a|
          options[:worker_timeout] = a
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

        opts.on '--ruby VAL', "Path to ruby which is used at -j option",
                "Also used as EnvUtil.rubybin by some assertion methods" do |a|
          options[:ruby] = a.split(/ /).reject(&:empty?)
        end

        opts.on '--timetable-data=FILE', "Path to timetable data" do |a|
          options[:timetable_data] = a
        end
      end

      class Worker
        def self.launch(ruby,args=[])
          scale = EnvUtil.timeout_scale
          io = IO.popen([*ruby, "-W1",
                        "#{__dir__}/unit/parallel.rb",
                        *("--timeout-scale=#{scale}" if scale),
                        *args], "rb+")
          new(io, io.pid, :waiting)
        end

        attr_reader :quit_called
        attr_accessor :start_time
        attr_accessor :response_at
        attr_accessor :current

        @@worker_number = 0

        def initialize(io, pid, status)
          @num = (@@worker_number += 1)
          @io = io
          @pid = pid
          @status = status
          @file = nil
          @real_file = nil
          @loadpath = []
          @hooks = {}
          @quit_called = false
          @response_at = nil
        end

        def name
          "Worker #{@num}"
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
            @start_time = Time.now
            @response_at = @start_time
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
          @response_at = Time.now
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
        warn "A test worker crashed. It might be an interpreter bug or"
        warn "a bug in test/unit/parallel.rb. Try again without the -j"
        warn "option."
        warn ""
        if File.exist?('core')
          require 'fileutils'
          require 'time'
          Dir.glob('/tmp/test-unit-core.*').each do |f|
            if Time.now - File.mtime(f) > 7 * 24 * 60 * 60 # 7 days
              warn "Deleting an old core file: #{f}"
              FileUtils.rm(f)
            end
          end
          core_path = "/tmp/test-unit-core.#{Time.now.utc.iso8601}"
          warn "A core file is found. Saving it at: #{core_path.dump}"
          FileUtils.mv('core', core_path)
          cmd = ['gdb', RbConfig.ruby, '-c', core_path, '-ex', 'bt', '-batch']
          p cmd # debugging why it's not working
          system(*cmd)
        end
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

      def quit_workers(&cond)
        return if @workers.empty?
        closed = [] if cond
        @workers.reject! do |worker|
          next unless cond&.call(worker)
          begin
            Timeout.timeout(1) do
              worker.quit
            end
          rescue Errno::EPIPE
          rescue Timeout::Error
          end
          closed&.push worker
          begin
            Timeout.timeout(0.2) do
              worker.close
            end
          rescue Timeout::Error
            worker.kill
            retry
          end
          @ios.delete worker.io
        end

        return if (closed ||= @workers).empty?
        pids = closed.map(&:pid)
        begin
          Timeout.timeout(0.2 * closed.size) do
            Process.waitall
          end
        rescue Timeout::Error
          if pids
            Process.kill(:KILL, *pids) rescue nil
            pids = nil
            retry
          end
        end
        @workers.clear unless cond
        closed
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
        when /^start (.+?)$/
          worker.current = Marshal.load($1.unpack1("m"))
        when /^done (.+?)$/
          begin
            r = Marshal.load($1.unpack1("m"))
          rescue
            print "unknown object: #{$1.unpack1("m").dump}"
            return true
          end
          result << r[0..1] unless r[0..1] == [nil,nil]
          rep    << {file: worker.real_file, report: r[2], result: r[3], testcase: r[5]}
          $:.push(*r[4]).uniq!
          jobs_status(worker) if @options[:job_status] == :replace

          return true
        when /^record (.+?)$/
          begin
            r = Marshal.load($1.unpack1("m"))

            suite = r.first
            key = [worker.name, suite]
            if @records[key]
              @records[key][1] = worker.start_time = Time.now
            else
              @records[key] = [worker.start_time, Time.now]
            end
          rescue => e
            print "unknown record: #{e.message} #{$1.unpack1("m").dump}"
            return true
          end
          record(fake_class(r[0]), *r[1..-1])
        when /^p (.+?)$/
          del_jobs_status
          print $1.unpack1("m")
          jobs_status(worker) if @options[:job_status] == :replace
        when /^after (.+?)$/
          @warnings << Marshal.load($1.unpack1("m"))
        when /^bye (.+?)$/
          after_worker_down worker, Marshal.load($1.unpack1("m"))
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
        @records = {}

        if @options[:parallel] < 1
          warn "Error: parameter of -j option should be greater than 0."
          return
        end

        # Require needed thing for parallel running
        require 'timeout'
        @tasks = @order.group(@order.sort_by_string(@files)) # Array of filenames.

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
          while true
            newjobs = [@tasks.size, @options[:parallel]].min - @workers.size
            if newjobs > 0
              if @jobserver
                t = @jobserver[0].read_nonblock(newjobs, exception: false)
                @job_tokens << t if String === t
                newjobs = @job_tokens.size + 1 - @workers.size
              end
              newjobs.times {launch_worker}
            end

            timeout = [(@workers.filter_map {|w| w.response_at}.min&.-(Time.now) || 0), 0].max + @worker_timeout

            if !(_io = IO.select(@ios, nil, nil, timeout))
              timeout = Time.now - @worker_timeout
              quit_workers {|w| w.response_at&.<(timeout) }&.map {|w|
                rep << {file: w.real_file, result: nil, testcase: w.current[0], error: w.current}
              }
            elsif _io.first.any? {|io|
              @need_quit or
                (deal(io, type, result, rep).nil? and
                 !@workers.any? {|x| [:running, :prepare].include? x.status})
            }
              break
            end
            if @tasks.empty?
              break if @workers.empty?
              next # wait for all workers to finish
            end
          end
        rescue Interrupt => ex
          @interrupt = ex
          return result
        ensure
          if file = @options[:timetable_data]
            File.open(file, 'w'){|f|
              @records.each{|(worker, suite), (st, ed)|
                f.puts '[' + [worker.dump, suite.dump, st.to_f * 1_000, ed.to_f * 1_000].join(", ") + '],'
              }
            }
          end

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
            suites, rep = rep.partition {|r|
              r[:testcase] && r[:file] &&
                (!r.key?(:report) || r[:report].any? {|e| !e[2].is_a?(Test::Unit::PendedError)})
            }
            suites.map {|r| File.realpath(r[:file])}.uniq.each {|file| require file}
            del_status_line or puts
            error, suites = suites.partition {|r| r[:error]}
            unless suites.empty?
              puts "\n""Retrying..."
              @verbose = options[:verbose]
              suites.map! {|r| ::Object.const_get(r[:testcase])}
              _run_suites(suites, type)
            end
            unless error.empty?
              puts "\n""Retrying hung up testcases..."
              error = error.map do |r|
                begin
                  ::Object.const_get(r[:testcase])
                rescue NameError
                  # testcase doesn't specify the correct case, so show `r` for information
                  require 'pp'

                  $stderr.puts "Retrying is failed because the file and testcase is not consistent:"
                  PP.pp r, $stderr
                  @errors += 1
                  nil
                end
              end.compact
              verbose = @verbose
              job_status = options[:job_status]
              options[:verbose] = @verbose = true
              options[:job_status] = :normal
              result.concat _run_suites(error, type)
              options[:verbose] = @verbose = verbose
              options[:job_status] = job_status
            end
            @options[:parallel] = parallel
          end
          unless @options[:retry]
            del_status_line or puts
          end
          unless rep.empty?
            rep.each do |r|
              if r[:error]
                puke(*r[:error], Timeout::Error.new)
                next
              end
              r[:report]&.each do |f|
                puke(*f) if f
              end
            end
            if @options[:retry]
              rep.each do |x|
                (e, f, s = x[:result]) or next
                @errors   += e
                @failures += f
                @skips    += s
              end
            end
          end
          unless @warnings.empty?
            warn ""
            @warnings.uniq! {|w| w[1].message}
            @warnings.each do |w|
              @errors += 1
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
        if writer = @options[:launchable_test_reports]
          location = nil
          if suite.respond_to?(:instance_method)
            location = suite.instance_method(method).source_location
          end
          if location && path = location.first
            # Launchable JSON schema is defined at
            # https://github.com/search?q=repo%3Alaunchableinc%2Fcli+https%3A%2F%2Flaunchableinc.com%2Fschema%2FRecordTestInput&type=code.
            e = case error
                when nil
                  status = 'TEST_PASSED'
                  nil
                when Test::Unit::PendedError
                  status = 'TEST_SKIPPED'
                  "Skipped:\n#{suite.name}##{method} [#{location error}]:\n#{error.message}\n"
                when Test::Unit::AssertionFailedError
                  status = 'TEST_FAILED'
                  "Failure:\n#{suite.name}##{method} [#{location error}]:\n#{error.message}\n"
                when Timeout::Error
                  status = 'TEST_FAILED'
                  "Timeout:\n#{suite.name}##{method}\n"
                else
                  status = 'TEST_FAILED'
                  bt = Test::filter_backtrace(error.backtrace).join "\n    "
                  "Error:\n#{suite.name}##{method}:\n#{error.class}: #{error.message.b}\n    #{bt}\n"
                end
            writer.sync_write_object do
              writer.write_key_value('testPath', "file=#{path}#class=#{suite.name}#testcase=#{method}")
              writer.write_key_value('status', status)
              writer.write_key_value('duration', time)
              writer.write_key_value('createdAt', Time.now.to_s)
              writer.write_key_value('stderr', e) if e
            end
          end
        end
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
        opts.on '--launchable-test-reports=PATH', String, 'Report test results in Launchable JSON format' do |path|
          require 'json'
          options[:launchable_test_reports] = writer = JsonStreamWriter.new(path)
          writer.write_array('testCases')
        end
      end
      ##
      # JsonStreamWriter writes a JSON file using a stream.
      # By utilizing a stream, we can minimize memory usage, especially for large files.
      class JsonStreamWriter
        def initialize(path)
          @path = path
          @indent_level = 0
          @is_first_key_val = true
          @is_first_obj = true
          @file = nil
        end

        # In parallel testing, test results are sometimes written simultaneously.
        # To address this, this method locks the file during the writing process.
        def sync_write_object
          File.open(@path, File::RDWR|File::CREAT, 0644) {|f|
            @file = f
            if @is_first_obj
              @file.write("{")
              write_new_line
              @is_first_obj = false
            else
              write_comma
              write_new_line
            end
            @indent_level += 1
            write_indent
            @file.write("{")
            write_new_line
            @indent_level += 1
            yield
            @indent_level -= 1
            write_new_line
            write_indent
            @file.write("}")
            @indent_level -= 1
            @is_first_key_val = true
          }
        end

        def write_array(key)
          File.open(@path, File::RDWR|File::CREAT, 0644) {|f|
            @file = f
            @indent_level += 1
            write_indent
            @file.write(to_json_str(key))
            write_colon
            @file.write(" ", "[")
            write_new_line
          }
        end

        def write_key_value(key, value)
          if @is_first_key_val
            @is_first_key_val = false
          else
            write_comma
            write_new_line
          end
          write_indent
          @file.write(to_json_str(key))
          write_colon
          @file.write(" ")
          @file.write(to_json_str(value))
        end

        def close
          File.open(@path, File::RDWR|File::CREAT, 0644) {|f|
            @file = f
            close_array
            @indent_level -= 1
            write_new_line
            @file.write("}")
            @file.flush
            @file.close
          }
        end

        private
        def to_json_str(obj)
          JSON.dump(obj)
        end

        def write_indent
          @file.write(" " * 2 * @indent_level)
        end

        def write_new_line
          @file.write("\n")
        end

        def write_comma
          @file.write(',')
        end

        def write_colon
          @file.write(":")
        end

        def close_array
          write_new_line
          write_indent
          @file.write("]")
          @indent_level -= 1
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
        return if !@options[:job_status] or @verbose
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
        options[:job_status] ||= @tty ? :replace : :normal unless @verbose
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
        total = suites.sum {|suite|
          methods = suite.send(type)
          if filter
            methods.count {|method| filter === "#{suite}##{method}"}
          else
            methods.size
          end
        }
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
          @failed_output.print(sep, @colorize.decorate(first, color), msg, "\n")
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
          when /\A\.*[EFST][EFST.]*\z/
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

    module OutputOption # :nodoc: all
      def setup_options(parser, options)
        super
        parser.separator "output options:"

        options[:failed_output] = $stdout
        parser.on '--stderr-on-failure', 'Use stderr to print failure messages' do
          options[:failed_output] = $stderr
        end
        parser.on '--stdout-on-failure', 'Use stdout to print failure messages', '(default)' do
          options[:failed_output] = $stdout
        end
      end

      def process_args(args = [])
        return @options if @options
        options = super
        @failed_output = options[:failed_output]
        options
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
          Test::Unit::TestCase.class_eval do
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
          Test::Unit::TestCase.class_eval do
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
        @load_failed = errors.size.nonzero?
        result
      end

      def run(*)
        super or @load_failed
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

    class Runner # :nodoc: all

      attr_accessor :report, :failures, :errors, :skips # :nodoc:
      attr_accessor :assertion_count                    # :nodoc:
      attr_writer   :test_count                         # :nodoc:
      attr_accessor :start_time                         # :nodoc:
      attr_accessor :help                               # :nodoc:
      attr_accessor :verbose                            # :nodoc:
      attr_writer   :options                            # :nodoc:

      ##
      # :attr:
      #
      # if true, installs an "INFO" signal handler (only available to BSD and
      # OS X users) which prints diagnostic information about the test run.
      #
      # This is auto-detected by default but may be overridden by custom
      # runners.

      attr_accessor :info_signal

      ##
      # Lazy accessor for options.

      def options
        @options ||= {seed: 42}
      end

      @@installed_at_exit ||= false
      @@out = $stdout
      @@after_tests = []
      @@current_repeat_count = 0

      ##
      # A simple hook allowing you to run a block of code after _all_ of
      # the tests are done. Eg:
      #
      #   Test::Unit::Runner.after_tests { p $debugging_info }

      def self.after_tests &block
        @@after_tests << block
      end

      ##
      # Returns the stream to use for output.

      def self.output
        @@out
      end

      ##
      # Sets Test::Unit::Runner to write output to +stream+.  $stdout is the default
      # output

      def self.output= stream
        @@out = stream
      end

      ##
      # Tells Test::Unit::Runner to delegate to +runner+, an instance of a
      # Test::Unit::Runner subclass, when Test::Unit::Runner#run is called.

      def self.runner= runner
        @@runner = runner
      end

      ##
      # Returns the Test::Unit::Runner subclass instance that will be used
      # to run the tests. A Test::Unit::Runner instance is the default
      # runner.

      def self.runner
        @@runner ||= self.new
      end

      ##
      # Return all plugins' run methods (methods that start with "run_").

      def self.plugins
        @@plugins ||= (["run_tests"] +
                      public_instance_methods(false).
                      grep(/^run_/).map { |s| s.to_s }).uniq
      end

      ##
      # Return the IO for output.

      def output
        self.class.output
      end

      def puts *a  # :nodoc:
        output.puts(*a)
      end

      def print *a # :nodoc:
        output.print(*a)
      end

      def test_count # :nodoc:
        @test_count ||= 0
      end

      ##
      # Runner for a given +type+ (eg, test vs bench).

      def self.current_repeat_count
        @@current_repeat_count
      end

      def _run_anything type
        suites = Test::Unit::TestCase.send "#{type}_suites"
        return if suites.empty?

        suites = @order.sort_by_name(suites)

        puts
        puts "# Running #{type}s:"
        puts

        @test_count, @assertion_count = 0, 0
        test_count = assertion_count = 0
        sync = output.respond_to? :"sync=" # stupid emacs
        old_sync, output.sync = output.sync, true if sync

        @@current_repeat_count = 0
        begin
          start = Time.now

          results = _run_suites suites, type

          @test_count      = results.inject(0) { |sum, (tc, _)| sum + tc }
          @assertion_count = results.inject(0) { |sum, (_, ac)| sum + ac }
          test_count      += @test_count
          assertion_count += @assertion_count
          t = Time.now - start
          @@current_repeat_count += 1
          unless @repeat_count
            puts
            puts
          end
          puts "Finished%s %ss in %.6fs, %.4f tests/s, %.4f assertions/s.\n" %
              [(@repeat_count ? "(#{@@current_repeat_count}/#{@repeat_count}) " : ""), type,
                t, @test_count.fdiv(t), @assertion_count.fdiv(t)]
        end while @repeat_count && @@current_repeat_count < @repeat_count &&
                  report.empty? && failures.zero? && errors.zero?

        output.sync = old_sync if sync

        report.each_with_index do |msg, i|
          puts "\n%3d) %s" % [i + 1, msg]
        end

        puts
        @test_count      = test_count
        @assertion_count = assertion_count

        # In parallel testing, `at_exit` block is called before all tests are finished.
        # Therefore, we invoke the `close` method here.
        if writer = @options[:launchable_test_reports]
          puts "called"
          writer.close
        end

        status
      end

      ##
      # Run a single +suite+ for a given +type+.

      def _run_suite suite, type
        header = "#{type}_suite_header"
        puts send(header, suite) if respond_to? header

        filter = options[:filter]

        all_test_methods = suite.send "#{type}_methods"
        if filter
          all_test_methods.select! {|method|
            filter === "#{suite}##{method}"
          }
        end
        all_test_methods = @order.sort_by_name(all_test_methods)

        leakchecker = LeakChecker.new
        if ENV["LEAK_CHECKER_TRACE_OBJECT_ALLOCATION"]
          require "objspace"
          trace = true
        end

        assertions = all_test_methods.map { |method|

          inst = suite.new method
          _start_method(inst)
          inst._assertions = 0

          print "#{suite}##{method.inspect.sub(/\A:/, '')} = " if @verbose

          start_time = Time.now if @verbose
          result =
            if trace
              ObjectSpace.trace_object_allocations {inst.run self}
            else
              inst.run self
            end

          print "%.2f s = " % (Time.now - start_time) if @verbose
          print result
          puts if @verbose
          $stdout.flush

          unless defined?(RubyVM::RJIT) && RubyVM::RJIT.enabled? # compiler process is wrongly considered as leak
            leakchecker.check("#{inst.class}\##{inst.__name__}")
          end

          _end_method(inst)

          inst._assertions
        }
        return assertions.size, assertions.inject(0) { |sum, n| sum + n }
      end

      def _start_method(inst)
      end
      def _end_method(inst)
      end

      ##
      # Record the result of a single test. Makes it very easy to gather
      # information. Eg:
      #
      #   class StatisticsRecorder < Test::Unit::Runner
      #     def record suite, method, assertions, time, error
      #       # ... record the results somewhere ...
      #     end
      #   end
      #
      #   Test::Unit::Runner.runner = StatisticsRecorder.new
      #
      # NOTE: record might be sent more than once per test.  It will be
      # sent once with the results from the test itself.  If there is a
      # failure or error in teardown, it will be sent again with the
      # error or failure.

      def record suite, method, assertions, time, error
      end

      def location e # :nodoc:
        last_before_assertion = ""

        return '<empty>' unless e&.backtrace # SystemStackError can return nil.

        e.backtrace.reverse_each do |s|
          break if s =~ /in .(assert|refute|flunk|pass|fail|raise|must|wont)/
          last_before_assertion = s
        end
        last_before_assertion.sub(/:in .*$/, '')
      end

      ##
      # Writes status for failed test +meth+ in +klass+ which finished with
      # exception +e+

      def initialize # :nodoc:
        @report = []
        @errors = @failures = @skips = 0
        @verbose = false
        @mutex = Thread::Mutex.new
        @info_signal = Signal.list['INFO']
        @repeat_count = nil
      end

      def synchronize # :nodoc:
        if @mutex then
          @mutex.synchronize { yield }
        else
          yield
        end
      end

      def inspect
        "#<#{self.class.name}: " <<
        instance_variables.filter_map do |var|
          next if var == :@option_parser # too big
          "#{var}=#{instance_variable_get(var).inspect}"
        end.join(", ") << ">"
      end

      ##
      # Top level driver, controls all output and filtering.

      def _run args = []
        args = process_args args # ARGH!! blame test/unit process_args
        self.options.merge! args

        puts "Run options: #{help}"

        self.class.plugins.each do |plugin|
          send plugin
          break unless report.empty?
        end

        return (failures + errors).nonzero? # or return nil...
      rescue Interrupt
        abort 'Interrupted'
      end

      ##
      # Runs test suites matching +filter+.

      def run_tests
        _run_anything :test
      end

      ##
      # Writes status to +io+

      def status io = self.output
        format = "%d tests, %d assertions, %d failures, %d errors, %d skips"
        io.puts format % [test_count, assertion_count, failures, errors, skips]
      end

      prepend Test::Unit::Options
      prepend Test::Unit::StatusLine
      prepend Test::Unit::Parallel
      prepend Test::Unit::Statistics
      prepend Test::Unit::Skipping
      prepend Test::Unit::GlobOption
      prepend Test::Unit::OutputOption
      prepend Test::Unit::RepeatOption
      prepend Test::Unit::LoadPathOption
      prepend Test::Unit::GCOption
      prepend Test::Unit::ExcludesOption
      prepend Test::Unit::TimeoutOption
      prepend Test::Unit::RunCount

      ##
      # Begins the full test run. Delegates to +runner+'s #_run method.

      def run(argv = [])
        self.class.runner._run(argv)
      rescue NoMemoryError
        system("cat /proc/meminfo") if File.exist?("/proc/meminfo")
        system("ps x -opid,args,%cpu,%mem,nlwp,rss,vsz,wchan,stat,start,time,etime,blocked,caught,ignored,pending,f") if File.exist?("/bin/ps")
        raise
      end

      @@stop_auto_run = false
      def self.autorun
        at_exit {
          Test::Unit::RunCount.run_once {
            exit(Test::Unit::Runner.new.run(ARGV) || true)
          } unless @@stop_auto_run
        } unless @@installed_at_exit
        @@installed_at_exit = true
      end

      alias orig_run_suite _run_suite

      # Overriding of Test::Unit::Runner#puke
      def puke klass, meth, e
        n = report.size
        e = case e
            when Test::Unit::PendedError then
              @skips += 1
              return "S" unless @verbose
              "Skipped:\n#{klass}##{meth} [#{location e}]:\n#{e.message}\n"
            when Test::Unit::AssertionFailedError then
              @failures += 1
              "Failure:\n#{klass}##{meth} [#{location e}]:\n#{e.message}\n"
            when Timeout::Error
              @errors += 1
              "Timeout:\n#{klass}##{meth}\n"
            else
              @errors += 1
              bt = Test::filter_backtrace(e.backtrace).join "\n    "
              "Error:\n#{klass}##{meth}:\n#{e.class}: #{e.message.b}\n    #{bt}\n"
            end
        @report << e
        rep = e[0, 1]
        if Test::Unit::PendedError === e and /no message given\z/ =~ e.message
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

Test::Unit::Runner.autorun
