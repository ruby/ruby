# frozen_string_literal: true

require_relative '../../envutil'

module Test
  module Unit
    module CoreAssertions
      include MiniTest::Assertions

      def mu_pp(obj) #:nodoc:
        obj.pretty_inspect.chomp
      end

      def assert_file
        AssertFile
      end

      FailDesc = proc do |status, message = "", out = ""|
        pid = status.pid
        now = Time.now
        faildesc = proc do
          if signo = status.termsig
            signame = Signal.signame(signo)
            sigdesc = "signal #{signo}"
          end
          log = EnvUtil.diagnostic_reports(signame, pid, now)
          if signame
            sigdesc = "SIG#{signame} (#{sigdesc})"
          end
          if status.coredump?
            sigdesc = "#{sigdesc} (core dumped)"
          end
          full_message = ''.dup
          message = message.call if Proc === message
          if message and !message.empty?
            full_message << message << "\n"
          end
          full_message << "pid #{pid}"
          full_message << " exit #{status.exitstatus}" if status.exited?
          full_message << " killed by #{sigdesc}" if sigdesc
          if out and !out.empty?
            full_message << "\n" << out.b.gsub(/^/, '| ')
            full_message.sub!(/(?<!\n)\z/, "\n")
          end
          if log
            full_message << "Diagnostic reports:\n" << log.b.gsub(/^/, '| ')
          end
          full_message
        end
        faildesc
      end

      def assert_in_out_err(args, test_stdin = "", test_stdout = [], test_stderr = [], message = nil,
                            success: nil, **opt)
        args = Array(args).dup
        args.insert((Hash === args[0] ? 1 : 0), '--disable=gems')
        stdout, stderr, status = EnvUtil.invoke_ruby(args, test_stdin, true, true, **opt)
        if signo = status.termsig
          EnvUtil.diagnostic_reports(Signal.signame(signo), status.pid, Time.now)
        end
        if block_given?
          raise "test_stdout ignored, use block only or without block" if test_stdout != []
          raise "test_stderr ignored, use block only or without block" if test_stderr != []
          yield(stdout.lines.map {|l| l.chomp }, stderr.lines.map {|l| l.chomp }, status)
        else
          all_assertions(message) do |a|
            [["stdout", test_stdout, stdout], ["stderr", test_stderr, stderr]].each do |key, exp, act|
              a.for(key) do
                if exp.is_a?(Regexp)
                  assert_match(exp, act)
                elsif exp.all? {|e| String === e}
                  assert_equal(exp, act.lines.map {|l| l.chomp })
                else
                  assert_pattern_list(exp, act)
                end
              end
            end
            unless success.nil?
              a.for("success?") do
                if success
                  assert_predicate(status, :success?)
                else
                  assert_not_predicate(status, :success?)
                end
              end
            end
          end
          status
        end
      end

      ABORT_SIGNALS = Signal.list.values_at(*%w"ILL ABRT BUS SEGV TERM")

      def assert_separately(args, file = nil, line = nil, src, ignore_stderr: nil, **opt)
        unless file and line
          loc, = caller_locations(1,1)
          file ||= loc.path
          line ||= loc.lineno
        end
        src = <<eom
# -*- coding: #{line += __LINE__; src.encoding}; -*-
  require #{__dir__.dump};include Test::Unit::Assertions
  END {
    puts [Marshal.dump($!)].pack('m'), "assertions=\#{self._assertions}"
  }
#{line -= __LINE__; src}
  class Test::Unit::Runner
    @@stop_auto_run = true
  end
eom
        args = args.dup
        args.insert((Hash === args.first ? 1 : 0), "-w", "--disable=gems", *$:.map {|l| "-I#{l}"})
        stdout, stderr, status = EnvUtil.invoke_ruby(args, src, true, true, **opt)
        abort = status.coredump? || (status.signaled? && ABORT_SIGNALS.include?(status.termsig))
        assert(!abort, FailDesc[status, nil, stderr])
        self._assertions += stdout[/^assertions=(\d+)/, 1].to_i
        begin
          res = Marshal.load(stdout.unpack("m")[0])
        rescue => marshal_error
          ignore_stderr = nil
        end
        if res
          if bt = res.backtrace
            bt.each do |l|
              l.sub!(/\A-:(\d+)/){"#{file}:#{line + $1.to_i}"}
            end
            bt.concat(caller)
          else
            res.set_backtrace(caller)
          end
          raise res unless SystemExit === res
        end

        # really is it succeed?
        unless ignore_stderr
          # the body of assert_separately must not output anything to detect error
          assert(stderr.empty?, FailDesc[status, "assert_separately failed with error message", stderr])
        end
        assert(status.success?, FailDesc[status, "assert_separately failed", stderr])
        raise marshal_error if marshal_error
      end

      class << (AssertFile = Struct.new(:failure_message).new)
        include CoreAssertions
        def assert_file_predicate(predicate, *args)
          if /\Anot_/ =~ predicate
            predicate = $'
            neg = " not"
          end
          result = File.__send__(predicate, *args)
          result = !result if neg
          mesg = "Expected file ".dup << args.shift.inspect
          mesg << "#{neg} to be #{predicate}"
          mesg << mu_pp(args).sub(/\A\[(.*)\]\z/m, '(\1)') unless args.empty?
          mesg << " #{failure_message}" if failure_message
          assert(result, mesg)
        end
        alias method_missing assert_file_predicate

        def for(message)
          clone.tap {|a| a.failure_message = message}
        end
      end

      class AllFailures
        attr_reader :failures

        def initialize
          @count = 0
          @failures = {}
        end

        def for(key)
          @count += 1
          yield
        rescue Exception => e
          @failures[key] = [@count, e]
        end

        def foreach(*keys)
          keys.each do |key|
            @count += 1
            begin
              yield key
            rescue Exception => e
              @failures[key] = [@count, e]
            end
          end
        end

        def message
          i = 0
          total = @count.to_s
          fmt = "%#{total.size}d"
          @failures.map {|k, (n, v)|
            v = v.message
            "\n#{i+=1}. [#{fmt%n}/#{total}] Assertion for #{k.inspect}\n#{v.b.gsub(/^/, '   | ').force_encoding(v.encoding)}"
          }.join("\n")
        end

        def pass?
          @failures.empty?
        end
      end

      def assert_all_assertions(msg = nil)
        all = AllFailures.new
        yield all
      ensure
        assert(all.pass?, message(msg) {all.message.chomp(".")})
      end
      alias all_assertions assert_all_assertions

    end
  end
end
