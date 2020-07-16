# frozen_string_literal: true

module Test
  module Unit
    module Assertions
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

    module CoreAssertions
      if defined?(MiniTest)
        require_relative '../../envutil'
        # for ruby core testing
        include MiniTest::Assertions

        # Compatibility hack for assert_raise
        Test::Unit::AssertionFailedError = MiniTest::Assertion
      else
        module MiniTest
          class Assertion < Exception; end
          class Skip < Assertion; end
        end

        require 'pp'
        require_relative 'envutil'
        include Test::Unit::Assertions
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
        desc = FailDesc[status, message, stderr]
        if block_given?
          raise "test_stdout ignored, use block only or without block" if test_stdout != []
          raise "test_stderr ignored, use block only or without block" if test_stderr != []
          yield(stdout.lines.map {|l| l.chomp }, stderr.lines.map {|l| l.chomp }, status)
        else
          all_assertions(desc) do |a|
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

      if defined?(RubyVM::InstructionSequence)
        def syntax_check(code, fname, line)
          code = code.dup.force_encoding(Encoding::UTF_8)
          RubyVM::InstructionSequence.compile(code, fname, fname, line)
          :ok
        ensure
          raise if SyntaxError === $!
        end
      else
        def syntax_check(code, fname, line)
          code = code.b
          code.sub!(/\A(?:\xef\xbb\xbf)?(\s*\#.*$)*(\n)?/n) {
            "#$&#{"\n" if $1 && !$2}BEGIN{throw tag, :ok}\n"
          }
          code = code.force_encoding(Encoding::UTF_8)
          catch {|tag| eval(code, binding, fname, line - 1)}
        end
      end

      def assert_no_memory_leak(args, prepare, code, message=nil, limit: 2.0, rss: false, **opt)
        # TODO: consider choosing some appropriate limit for MJIT and stop skipping this once it does not randomly fail
        pend 'assert_no_memory_leak may consider MJIT memory usage as leak' if defined?(RubyVM::MJIT) && RubyVM::MJIT.enabled?

        require_relative '../../memory_status'
        raise MiniTest::Skip, "unsupported platform" unless defined?(Memory::Status)

        token = "\e[7;1m#{$$.to_s}:#{Time.now.strftime('%s.%L')}:#{rand(0x10000).to_s(16)}:\e[m"
        token_dump = token.dump
        token_re = Regexp.quote(token)
        envs = args.shift if Array === args and Hash === args.first
        args = [
          "--disable=gems",
          "-r", File.expand_path("../../../memory_status", __FILE__),
          *args,
          "-v", "-",
        ]
        if defined? Memory::NO_MEMORY_LEAK_ENVS then
          envs ||= {}
          newenvs = envs.merge(Memory::NO_MEMORY_LEAK_ENVS) { |_, _, _| break }
          envs = newenvs if newenvs
        end
        args.unshift(envs) if envs
        cmd = [
          'END {STDERR.puts '"#{token_dump}"'"FINAL=#{Memory::Status.new}"}',
          prepare,
          'STDERR.puts('"#{token_dump}"'"START=#{$initial_status = Memory::Status.new}")',
          '$initial_size = $initial_status.size',
          code,
          'GC.start',
        ].join("\n")
        _, err, status = EnvUtil.invoke_ruby(args, cmd, true, true, **opt)
        before = err.sub!(/^#{token_re}START=(\{.*\})\n/, '') && Memory::Status.parse($1)
        after = err.sub!(/^#{token_re}FINAL=(\{.*\})\n/, '') && Memory::Status.parse($1)
        assert(status.success?, FailDesc[status, message, err])
        ([:size, (rss && :rss)] & after.members).each do |n|
          b = before[n]
          a = after[n]
          next unless a > 0 and b > 0
          assert_operator(a.fdiv(b), :<, limit, message(message) {"#{n}: #{b} => #{a}"})
        end
      rescue LoadError
        pend
      end

      # :call-seq:
      #   assert_nothing_raised( *args, &block )
      #
      #If any exceptions are given as arguments, the assertion will
      #fail if one of those exceptions are raised. Otherwise, the test fails
      #if any exceptions are raised.
      #
      #The final argument may be a failure message.
      #
      #    assert_nothing_raised RuntimeError do
      #      raise Exception #Assertion passes, Exception is not a RuntimeError
      #    end
      #
      #    assert_nothing_raised do
      #      raise Exception #Assertion fails
      #    end
      def assert_nothing_raised(*args)
        self._assertions += 1
        if Module === args.last
          msg = nil
        else
          msg = args.pop
        end
        begin
          line = __LINE__; yield
        rescue MiniTest::Skip
          raise
        rescue Exception => e
          bt = e.backtrace
          as = e.instance_of?(MiniTest::Assertion)
          if as
            ans = /\A#{Regexp.quote(__FILE__)}:#{line}:in /o
            bt.reject! {|ln| ans =~ ln}
          end
          if ((args.empty? && !as) ||
              args.any? {|a| a.instance_of?(Module) ? e.is_a?(a) : e.class == a })
            msg = message(msg) {
              "Exception raised:\n<#{mu_pp(e)}>\n" +
              "Backtrace:\n" +
              e.backtrace.map{|frame| "  #{frame}"}.join("\n")
            }
            raise MiniTest::Assertion, msg.call, bt
          else
            raise
          end
        end
      end

      def prepare_syntax_check(code, fname = nil, mesg = nil, verbose: nil)
        fname ||= caller_locations(2, 1)[0]
        mesg ||= fname.to_s
        verbose, $VERBOSE = $VERBOSE, verbose
        case
        when Array === fname
          fname, line = *fname
        when defined?(fname.path) && defined?(fname.lineno)
          fname, line = fname.path, fname.lineno
        else
          line = 1
        end
        yield(code, fname, line, message(mesg) {
                if code.end_with?("\n")
                  "```\n#{code}```\n"
                else
                  "```\n#{code}\n```\n""no-newline"
                end
              })
      ensure
        $VERBOSE = verbose
      end

      def assert_valid_syntax(code, *args, **opt)
        prepare_syntax_check(code, *args, **opt) do |src, fname, line, mesg|
          yield if defined?(yield)
          assert_nothing_raised(SyntaxError, mesg) do
            assert_equal(:ok, syntax_check(src, fname, line), mesg)
          end
        end
      end

      def assert_normal_exit(testsrc, message = '', child_env: nil, **opt)
        assert_valid_syntax(testsrc, caller_locations(1, 1)[0])
        if child_env
          child_env = [child_env]
        else
          child_env = []
        end
        out, _, status = EnvUtil.invoke_ruby(child_env + %W'-W0', testsrc, true, :merge_to_stdout, **opt)
        assert !status.signaled?, FailDesc[status, message, out]
      end

      def assert_ruby_status(args, test_stdin="", message=nil, **opt)
        out, _, status = EnvUtil.invoke_ruby(args, test_stdin, true, :merge_to_stdout, **opt)
        desc = FailDesc[status, message, out]
        assert(!status.signaled?, desc)
        message ||= "ruby exit status is not success:"
        assert(status.success?, desc)
      end

      ABORT_SIGNALS = Signal.list.values_at(*%w"ILL ABRT BUS SEGV TERM")

      def separated_runner(out = nil)
        out = out ? IO.new(out, 'w') : STDOUT
        at_exit {
          out.puts [Marshal.dump($!)].pack('m'), "assertions=\#{self._assertions}"
        }
        Test::Unit::Runner.class_variable_set(:@@stop_auto_run, true)
      end

      def assert_separately(args, file = nil, line = nil, src, ignore_stderr: nil, **opt)
        unless file and line
          loc, = caller_locations(1,1)
          file ||= loc.path
          line ||= loc.lineno
        end
        capture_stdout = true
        unless /mswin|mingw/ =~ RUBY_PLATFORM
          capture_stdout = false
          opt[:out] = MiniTest::Unit.output
          res_p, res_c = IO.pipe
          opt[res_c.fileno] = res_c.fileno
        end
        src = <<eom
# -*- coding: #{line += __LINE__; src.encoding}; -*-
BEGIN {
  require "test/unit";include Test::Unit::Assertions;require #{(__dir__ + "/core_assertions").dump};include Test::Unit::CoreAssertions
  separated_runner #{res_c&.fileno}
}
#{line -= __LINE__; src}
eom
        args = args.dup
        args.insert((Hash === args.first ? 1 : 0), "-w", "--disable=gems", *$:.map {|l| "-I#{l}"})
        stdout, stderr, status = EnvUtil.invoke_ruby(args, src, capture_stdout, true, **opt)
      ensure
        if res_c
          res_c.close
          res = res_p.read
          res_p.close
        else
          res = stdout
        end
        raise if $!
        abort = status.coredump? || (status.signaled? && ABORT_SIGNALS.include?(status.termsig))
        assert(!abort, FailDesc[status, nil, stderr])
        self._assertions += res[/^assertions=(\d+)/, 1].to_i
        begin
          res = Marshal.load(res.unpack1("m"))
        rescue => marshal_error
          ignore_stderr = nil
          res = nil
        end
        if res and !(SystemExit === res)
          if bt = res.backtrace
            bt.each do |l|
              l.sub!(/\A-:(\d+)/){"#{file}:#{line + $1.to_i}"}
            end
            bt.concat(caller)
          else
            res.set_backtrace(caller)
          end
          raise res
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
      #   assert_raise( *args, &block )
      #
      #Tests if the given block raises an exception. Acceptable exception
      #types may be given as optional arguments. If the last argument is a
      #String, it will be used as the error message.
      #
      #    assert_raise do #Fails, no Exceptions are raised
      #    end
      #
      #    assert_raise NameError do
      #      puts x  #Raises NameError, so assertion succeeds
      #    end
      def assert_raise(*exp, &b)
        case exp.last
        when String, Proc
          msg = exp.pop
        end

        begin
          yield
        rescue MiniTest::Skip => e
          return e if exp.include? MiniTest::Skip
          raise e
        rescue Exception => e
          expected = exp.any? { |ex|
            if ex.instance_of? Module then
              e.kind_of? ex
            else
              e.instance_of? ex
            end
          }

          assert expected, proc {
            flunk(message(msg) {"#{mu_pp(exp)} exception expected, not #{mu_pp(e)}"})
          }

          return e
        ensure
          unless e
            exp = exp.first if exp.size == 1

            flunk(message(msg) {"#{mu_pp(exp)} expected but nothing was raised"})
          end
        end
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

      # pattern_list is an array which contains regexp and :*.
      # :* means any sequence.
      #
      # pattern_list is anchored.
      # Use [:*, regexp, :*] for non-anchored match.
      def assert_pattern_list(pattern_list, actual, message=nil)
        rest = actual
        anchored = true
        pattern_list.each_with_index {|pattern, i|
          if pattern == :*
            anchored = false
          else
            if anchored
              match = /\A#{pattern}/.match(rest)
            else
              match = pattern.match(rest)
            end
            unless match
              msg = message(msg) {
                expect_msg = "Expected #{mu_pp pattern}\n"
                if /\n[^\n]/ =~ rest
                  actual_mesg = +"to match\n"
                  rest.scan(/.*\n+/) {
                    actual_mesg << '  ' << $&.inspect << "+\n"
                  }
                  actual_mesg.sub!(/\+\n\z/, '')
                else
                  actual_mesg = "to match " + mu_pp(rest)
                end
                actual_mesg << "\nafter #{i} patterns with #{actual.length - rest.length} characters"
                expect_msg + actual_mesg
              }
              assert false, msg
            end
            rest = match.post_match
            anchored = true
          end
        }
        if anchored
          assert_equal("", rest)
        end
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

      # threads should respond to shift method.
      # Array can be used.
      def assert_join_threads(threads, message = nil)
        errs = []
        values = []
        while th = threads.shift
          begin
            values << th.value
          rescue Exception
            errs << [th, $!]
            th = nil
          end
        end
        values
      ensure
        if th&.alive?
          th.raise(Timeout::Error.new)
          th.join rescue errs << [th, $!]
        end
        if !errs.empty?
          msg = "exceptions on #{errs.length} threads:\n" +
            errs.map {|t, err|
            "#{t.inspect}:\n" +
              RUBY_VERSION >= "2.5.0" ? err.full_message(highlight: false, order: :top) : err.message
          }.join("\n---\n")
          if message
            msg = "#{message}\n#{msg}"
          end
          raise MiniTest::Assertion, msg
        end
      end

      def assert_all_assertions(msg = nil)
        all = AllFailures.new
        yield all
      ensure
        assert(all.pass?, message(msg) {all.message.chomp(".")})
      end
      alias all_assertions assert_all_assertions

      def message(msg = nil, *args, &default) # :nodoc:
        if Proc === msg
          super(nil, *args) do
            ary = [msg.call, (default.call if default)].compact.reject(&:empty?)
            if 1 < ary.length
              ary[0...-1] = ary[0...-1].map {|str| str.sub(/(?<!\.)\z/, '.') }
            end
            begin
              ary.join("\n")
            rescue Encoding::CompatibilityError
              ary.map(&:b).join("\n")
            end
          end
        else
          super
        end
      end

      def diff(exp, act)
        require 'pp'
        q = PP.new(+"")
        q.guard_inspect_key do
          q.group(2, "expected: ") do
            q.pp exp
          end
          q.text q.newline
          q.group(2, "actual: ") do
            q.pp act
          end
          q.flush
        end
        q.output
      end
    end
  end
end
