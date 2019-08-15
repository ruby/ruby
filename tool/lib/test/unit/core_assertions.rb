# frozen_string_literal: true

module Test
  module Unit
    module CoreAssertions
      if defined?(MiniTest)
        require_relative '../../envutil'
        # for ruby core testing
        include MiniTest::Assertions
      else
        require 'pp'
        require_relative 'envutil'
        include Test::Unit::Assertions

        def _assertions= n # :nodoc:
          @_assertions = n
        end

        def _assertions # :nodoc:
          @_assertions ||= 0
        end

        ##
        # Returns a proc that will output +msg+ along with the default message.

        def message msg = nil, ending = nil, &default
          proc {
            msg = msg.call.chomp(".") if Proc === msg
            custom_message = "#{msg}.\n" unless msg.nil? or msg.to_s.empty?
            "#{custom_message}#{default.call}#{ending || "."}"
          }
        end
      end

      def mu_pp(obj) #:nodoc:
        obj.pretty_inspect.chomp
      end

      def assert_file
        AssertFile
      end

      FailDesc = proc do |status, message = "", out = ""|
        now = Time.now
        proc do
          EnvUtil.failure_description(status, now, message, out)
        end
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

      def assert_ruby_status(args, test_stdin="", message=nil, **opt)
        out, _, status = EnvUtil.invoke_ruby(args, test_stdin, true, :merge_to_stdout, **opt)
        desc = FailDesc[status, message, out]
        assert(!status.signaled?, desc)
        message ||= "ruby exit status is not success:"
        assert(status.success?, desc)
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
  require "test/unit";include Test::Unit::Assertions;require #{(__dir__ + "/core_assertions").dump};include Test::Unit::CoreAssertions
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

      # :call-seq:
      #   assert_throw( tag, failure_message = nil, &block )
      #
      #Fails unless the given block throws +tag+, returns the caught
      #value otherwise.
      #
      #An optional failure message may be provided as the final argument.
      #
      #    tag = Object.new
      #    assert_throw(tag, "#{tag} was not thrown!") do
      #      throw tag
      #    end
      def assert_throw(tag, msg = nil)
        ret = catch(tag) do
          begin
            yield(tag)
          rescue UncaughtThrowError => e
            thrown = e.tag
          end
          msg = message(msg) {
            "Expected #{mu_pp(tag)} to have been thrown"\
            "#{%Q[, not #{thrown}] if thrown}"
          }
          assert(false, msg)
        end
        assert(true)
        ret
      end

      # :call-seq:
      #   assert_raise_with_message(exception, expected, msg = nil, &block)
      #
      #Tests if the given block raises an exception with the expected
      #message.
      #
      #    assert_raise_with_message(RuntimeError, "foo") do
      #      nil #Fails, no Exceptions are raised
      #    end
      #
      #    assert_raise_with_message(RuntimeError, "foo") do
      #      raise ArgumentError, "foo" #Fails, different Exception is raised
      #    end
      #
      #    assert_raise_with_message(RuntimeError, "foo") do
      #      raise "bar" #Fails, RuntimeError is raised but the message differs
      #    end
      #
      #    assert_raise_with_message(RuntimeError, "foo") do
      #      raise "foo" #Raises RuntimeError with the message, so assertion succeeds
      #    end
      def assert_raise_with_message(exception, expected, msg = nil, &block)
        case expected
        when String
          assert = :assert_equal
        when Regexp
          assert = :assert_match
        else
          raise TypeError, "Expected #{expected.inspect} to be a kind of String or Regexp, not #{expected.class}"
        end

        ex = m = nil
        EnvUtil.with_default_internal(expected.encoding) do
          ex = assert_raise(exception, msg || proc {"Exception(#{exception}) with message matches to #{expected.inspect}"}) do
            yield
          end
          m = ex.message
        end
        msg = message(msg, "") {"Expected Exception(#{exception}) was raised, but the message doesn't match"}

        if assert == :assert_equal
          assert_equal(expected, m, msg)
        else
          msg = message(msg) { "Expected #{mu_pp expected} to match #{mu_pp m}" }
          assert expected =~ m, msg
          block.binding.eval("proc{|_|$~=_}").call($~)
        end
        ex
      end

      def assert_warning(pat, msg = nil)
        result = nil
        stderr = EnvUtil.with_default_internal(pat.encoding) {
          EnvUtil.verbose_warning {
            result = yield
          }
        }
        msg = message(msg) {diff pat, stderr}
        assert(pat === stderr, msg)
        result
      end

      def assert_warn(*args)
        assert_warning(*args) {$VERBOSE = false; yield}
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
