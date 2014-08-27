$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../.."
require 'test/unit'

module Test
  module Unit
    class Worker < Runner # :nodoc:
      class << self
        undef autorun
      end

      alias orig_run_suite mini_run_suite
      undef _run_suite
      undef _run_suites
      undef run

      def increment_io(orig) # :nodoc:
        *rest, io = 32.times.inject([orig.dup]){|ios, | ios << ios.last.dup }
        rest.each(&:close)
        io
      end

      def _run_suites(suites, type) # :nodoc:
        suites.map do |suite|
          _run_suite(suite, type)
        end
      end

      def _run_suite(suite, type) # :nodoc:
        @partial_report = []
        orig_testout = MiniTest::Unit.output
        i,o = IO.pipe

        MiniTest::Unit.output = o
        orig_stdin, orig_stdout = $stdin, $stdout

        th = Thread.new do
          begin
            while buf = (self.verbose ? i.gets : i.readpartial(1024))
              _report "p", buf
            end
          rescue IOError
          rescue Errno::EPIPE
          end
        end

        e, f, s = @errors, @failures, @skips

        begin
          result = orig_run_suite(suite, type)
        rescue Interrupt
          @need_exit = true
          result = [nil,nil]
        end

        MiniTest::Unit.output = orig_testout
        $stdin = orig_stdin
        $stdout = orig_stdout

        o.close
        begin
          th.join
        rescue IOError
          raise unless ["stream closed","closed stream"].include? $!.message
        end
        i.close

        result << @partial_report
        @partial_report = nil
        result << [@errors-e,@failures-f,@skips-s]
        result << ($: - @old_loadpath)
        result << suite.name

        begin
          _report "done", Marshal.dump(result)
        rescue Errno::EPIPE; end
        return result
      ensure
        MiniTest::Unit.output = orig_stdout
        $stdin = orig_stdin if orig_stdin
        $stdout = orig_stdout if orig_stdout
        o.close if o && !o.closed?
        i.close if i && !i.closed?
      end

      def run(args = []) # :nodoc:
        process_args args
        @@stop_auto_run = true
        @opts = @options.dup
        @need_exit = false

        @old_loadpath = []
        begin
          begin
            @stdout = increment_io(STDOUT)
            @stdin = increment_io(STDIN)
          rescue
            exit 2
          end
          exit 2 unless @stdout && @stdin

          @stdout.sync = true
          _report "ready!"
          while buf = @stdin.gets
            case buf.chomp
            when /^loadpath (.+?)$/
              @old_loadpath = $:.dup
              $:.push(*Marshal.load($1.unpack("m")[0].force_encoding("ASCII-8BIT"))).uniq!
            when /^run (.+?) (.+?)$/
              _report "okay"

              @options = @opts.dup
              suites = MiniTest::Unit::TestCase.test_suites

              begin
                require $1
              rescue LoadError
                _report "after", Marshal.dump([$1, ProxyError.new($!)])
                _report "ready"
                next
              end
              _run_suites MiniTest::Unit::TestCase.test_suites-suites, $2.to_sym

              if @need_exit
                begin
                  _report "bye"
                rescue Errno::EPIPE; end
                exit
              else
                _report "ready"
              end
            when /^quit$/
              begin
                _report "bye"
              rescue Errno::EPIPE; end
              exit
            end
          end
        rescue Errno::EPIPE
        rescue Exception => e
          begin
            trace = e.backtrace
            err = ["#{trace.shift}: #{e.message} (#{e.class})"] + trace.map{|t| t.prepend("\t") }

            _report "bye", Marshal.dump(err.join("\n"))
          rescue Errno::EPIPE;end
          exit
        ensure
          @stdin.close if @stdin
          @stdout.close if @stdout
        end
      end

      def _report(res, *args) # :nodoc:
        res = "#{res} #{args.pack("m0")}" unless args.empty?
        @stdout.puts(res)
      end

      def puke(klass, meth, e) # :nodoc:
        if e.is_a?(MiniTest::Skip)
          new_e = MiniTest::Skip.new(e.message)
          new_e.set_backtrace(e.backtrace)
          e = new_e
        end
        @partial_report << [klass.name, meth, e.is_a?(MiniTest::Assertion) ? e : ProxyError.new(e)]
        super
      end
    end
  end
end

if $0 == __FILE__
  module Test
    module Unit
      class TestCase < MiniTest::Unit::TestCase # :nodoc: all
        undef on_parallel_worker?
        def on_parallel_worker?
          true
        end
      end
    end
  end
  require 'rubygems'
  module Gem # :nodoc:
  end
  class Gem::TestCase < MiniTest::Unit::TestCase # :nodoc:
    @@project_dir = File.expand_path('../../../..', __FILE__)
  end

  Test::Unit::Worker.new.run(ARGV)
end
