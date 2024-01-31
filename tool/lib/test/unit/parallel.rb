# frozen_string_literal: true

require_relative "../../../test/init"

module Test
  module Unit
    class Worker < Runner # :nodoc:
      class << self
        undef autorun
      end

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

      def _start_method(inst)
        _report "start", Marshal.dump([inst.class.name, inst.__name__])
      end

      def _run_suite(suite, type) # :nodoc:
        @partial_report = []
        orig_testout = Test::Unit::Runner.output
        i,o = IO.pipe

        Test::Unit::Runner.output = o
        orig_stdin, orig_stdout = $stdin, $stdout

        th = Thread.new do
          begin
            while buf = (self.verbose ? i.gets : i.readpartial(1024))
              _report "p", buf or break
            end
          rescue IOError
          end
        end

        e, f, s = @errors, @failures, @skips

        begin
          result = orig_run_suite(suite, type)
        rescue Interrupt
          @need_exit = true
          result = [nil,nil]
        end

        Test::Unit::Runner.output = orig_testout
        $stdin = orig_stdin
        $stdout = orig_stdout

        o.close
        begin
          th.join
        rescue IOError
          raise unless /stream closed|closed stream/ =~ $!.message
        end
        i.close

        result << @partial_report
        @partial_report = nil
        result << [@errors-e,@failures-f,@skips-s]
        result << ($: - @old_loadpath)
        result << suite.name

        _report "done", Marshal.dump(result)
        return result
      ensure
        Test::Unit::Runner.output = orig_stdout
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
              $:.push(*Marshal.load($1.unpack1("m").force_encoding("ASCII-8BIT"))).uniq!
            when /^run (.+?) (.+?)$/
              _report "okay"

              @options = @opts.dup
              suites = Test::Unit::TestCase.test_suites

              begin
                require File.realpath($1)
              rescue LoadError
                _report "after", Marshal.dump([$1, ProxyError.new($!)])
                _report "ready"
                next
              end
              _run_suites Test::Unit::TestCase.test_suites-suites, $2.to_sym

              if @need_exit
                _report "bye"
                exit
              else
                _report "ready"
              end
            when /^quit$/
              _report "bye"
              exit
            end
          end
        rescue Exception => e
          trace = e.backtrace || ['unknown method']
          err = ["#{trace.shift}: #{e.message} (#{e.class})"] + trace.map{|t| "\t" + t }

          if @stdout
            _report "bye", Marshal.dump(err.join("\n"))
          else
            raise "failed to report a failure due to lack of @stdout"
          end
          exit
        ensure
          @stdin.close if @stdin
          @stdout.close if @stdout
        end
      end

      def _report(res, *args) # :nodoc:
        @stdout.write(args.empty? ? "#{res}\n" : "#{res} #{args.pack("m0")}\n")
        true
      rescue Errno::EPIPE
      rescue TypeError => e
        abort("#{e.inspect} in _report(#{res.inspect}, #{args.inspect})\n#{e.backtrace.join("\n")}")
      end

      def puke(klass, meth, e) # :nodoc:
        if e.is_a?(Test::Unit::PendedError)
          new_e = Test::Unit::PendedError.new(e.message)
          new_e.set_backtrace(e.backtrace)
          e = new_e
        end
        @partial_report << [klass.name, meth, e.is_a?(Test::Unit::AssertionFailedError) ? e : ProxyError.new(e)]
        super
      end

      def record(suite, method, assertions, time, error) # :nodoc:
        case error
        when nil
        when Test::Unit::AssertionFailedError, Test::Unit::PendedError
          case error.cause
          when nil, Test::Unit::AssertionFailedError, Test::Unit::PendedError
          else
            bt = error.backtrace
            error = error.class.new(error.message)
            error.set_backtrace(bt)
          end
        else
          error = ProxyError.new(error)
        end
        _report "record", Marshal.dump([suite.name, method, assertions, time, error, suite.instance_method(method).source_location])
        super
      end
    end
  end
end

if $0 == __FILE__
  module Test
    module Unit
      class TestCase # :nodoc: all
        undef on_parallel_worker?
        def on_parallel_worker?
          true
        end
        def self.on_parallel_worker?
          true
        end
      end
    end
  end
  require 'rubygems'
  begin
    require 'rake'
  rescue LoadError
  end
  Test::Unit::Worker.new.run(ARGV)
end
