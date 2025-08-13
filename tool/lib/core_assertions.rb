# frozen_string_literal: true

module Test

  class << self
    ##
    # Filter object for backtraces.

    attr_accessor :backtrace_filter
  end

  class BacktraceFilter # :nodoc:
    def filter bt
      return ["No backtrace"] unless bt

      new_bt = []
      pattern = %r[/(?:lib\/test/|core_assertions\.rb:)]

      unless $DEBUG then
        bt.each do |line|
          break if pattern.match?(line)
          new_bt << line
        end

        new_bt = bt.reject { |line| pattern.match?(line) } if new_bt.empty?
        new_bt = bt.dup if new_bt.empty?
      else
        new_bt = bt.dup
      end

      new_bt
    end
  end

  self.backtrace_filter = BacktraceFilter.new

  def self.filter_backtrace bt # :nodoc:
    backtrace_filter.filter bt
  end

  module Unit
    module Assertions
      def assert_raises(*exp, &b)
        raise NoMethodError, "use assert_raise", caller
      end

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
          ending ||= (ending_pattern = /(?<!\.)\z/; ".")
          ending_pattern ||= /(?<!#{Regexp.quote(ending)})\z/
          msg = msg.call if Proc === msg
          ary = [msg, (default.call if default)].compact.reject(&:empty?)
          ary.map! {|str| str.to_s.sub(ending_pattern, ending) }
          begin
            ary.join("\n")
          rescue Encoding::CompatibilityError
            ary.map(&:b).join("\n")
          end
        }
      end
    end

    module CoreAssertions
      require_relative 'envutil'
      require 'pp'
      begin
        require '-test-/asan'
      rescue LoadError
      end

      nil.pretty_inspect

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
                            success: nil, failed: nil, **opt)
        args = Array(args).dup
        args.insert((Hash === args[0] ? 1 : 0), '--disable=gems')
        stdout, stderr, status = EnvUtil.invoke_ruby(args, test_stdin, true, true, **opt)
        desc = failed[status, message, stderr] if failed
        desc ||= FailDesc[status, message, stderr]
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
        # TODO: consider choosing some appropriate limit for RJIT and stop skipping this once it does not randomly fail
        pend 'assert_no_memory_leak may consider RJIT memory usage as leak' if defined?(RubyVM::RJIT) && RubyVM::RJIT.enabled?
        # For previous versions which implemented MJIT
        pend 'assert_no_memory_leak may consider MJIT memory usage as leak' if defined?(RubyVM::MJIT) && RubyVM::MJIT.enabled?
        # ASAN has the same problem - its shadow memory greatly increases memory usage
        # (plus asan has better ways to detect memory leaks than this assertion)
        pend 'assert_no_memory_leak may consider ASAN memory usage as leak' if defined?(Test::ASAN) && Test::ASAN.enabled?

        require_relative 'memory_status'
        raise Test::Unit::PendedError, "unsupported platform" unless defined?(Memory::Status)

        token_dump, token_re = new_test_token
        envs = args.shift if Array === args and Hash === args.first
        args = [
          "--disable=gems",
          "-r", File.expand_path("../memory_status", __FILE__),
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
          yield
        rescue Test::Unit::PendedError, *(Test::Unit::AssertionFailedError if args.empty?)
          raise
        rescue *(args.empty? ? Exception : args) => e
          msg = message(msg) {
            "Exception raised:\n<#{mu_pp(e)}>\n""Backtrace:\n" <<
            Test.filter_backtrace(e.backtrace).map{|frame| "  #{frame}"}.join("\n")
          }
          raise Test::Unit::AssertionFailedError, msg.call, e.backtrace
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

      def separated_runner(token, out = nil)
        include(*Test::Unit::TestCase.ancestors.select {|c| !c.is_a?(Class) })
        out = out ? IO.new(out, 'w') : STDOUT
        at_exit {
          out.puts "#{token}<error>", [Marshal.dump($!)].pack('m'), "#{token}</error>", "#{token}assertions=#{self._assertions}"
        }
        if defined?(Test::Unit::Runner)
          Test::Unit::Runner.class_variable_set(:@@stop_auto_run, true)
        elsif defined?(Test::Unit::AutoRunner)
          Test::Unit::AutoRunner.need_auto_run = false
        end
      end

      def assert_separately(args, file = nil, line = nil, src, ignore_stderr: nil, **opt)
        unless file and line
          loc, = caller_locations(1,1)
          file ||= loc.path
          line ||= loc.lineno
        end
        capture_stdout = true
        unless /mswin|mingw/ =~ RbConfig::CONFIG['host_os']
          capture_stdout = false
          opt[:out] = Test::Unit::Runner.output if defined?(Test::Unit::Runner)
          res_p, res_c = IO.pipe
          opt[:ios] = [res_c]
        end
        token_dump, token_re = new_test_token
        src = <<eom
# -*- coding: #{line += __LINE__; src.encoding}; -*-
BEGIN {
  require "test/unit";include Test::Unit::Assertions;require #{__FILE__.dump};include Test::Unit::CoreAssertions
  separated_runner #{token_dump}, #{res_c&.fileno || 'nil'}
}
#{line -= __LINE__; src}
eom
        args = args.dup
        args.insert((Hash === args.first ? 1 : 0), "-w", "--disable=gems", *$:.map {|l| "-I#{l}"})
        args << "--debug" if RUBY_ENGINE == 'jruby' # warning: tracing (e.g. set_trace_func) will not capture all events without --debug flag
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
        self._assertions += res[/^#{token_re}assertions=(\d+)/, 1].to_i
        begin
          res = Marshal.load(res[/^#{token_re}<error>\n\K.*\n(?=#{token_re}<\/error>$)/m].unpack1("m"))
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

      # Run Ractor-related test without influencing the main test suite
      def assert_ractor(src, args: [], require: nil, require_relative: nil, file: nil, line: nil, ignore_stderr: nil, **opt)
        return unless defined?(Ractor)

        # https://bugs.ruby-lang.org/issues/21262
        shim_value = "class Ractor; alias value take; end" unless Ractor.method_defined?(:value)
        shim_join = "class Ractor; alias join take; end" unless Ractor.method_defined?(:join)

        require = "require #{require.inspect}" if require
        if require_relative
          dir = File.dirname(caller_locations[0,1][0].absolute_path)
          full_path = File.expand_path(require_relative, dir)
          require = "#{require}; require #{full_path.inspect}"
        end

        assert_separately(args, file, line, <<~RUBY, ignore_stderr: ignore_stderr, **opt)
          #{shim_value}
          #{shim_join}
          #{require}
          previous_verbose = $VERBOSE
          $VERBOSE = nil
          Ractor.new {} # trigger initial warning
          $VERBOSE = previous_verbose
          #{src}
        RUBY
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
        rescue Test::Unit::PendedError => e
          return e if exp.include? Test::Unit::PendedError
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
        else
          assert_respond_to(expected, :===)
          assert = :assert_match
        end

        ex = m = nil
        EnvUtil.with_default_internal(of: expected) do
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

      # :call-seq:
      #   assert_raise_kind_of(*args, &block)
      #
      #Tests if the given block raises one of the given exceptions or
      #sub exceptions of the given exceptions.  If the last argument
      #is a String, it will be used as the error message.
      #
      #    assert_raise do #Fails, no Exceptions are raised
      #    end
      #
      #    assert_raise SystemCallErr do
      #      Dir.chdir(__FILE__) #Raises Errno::ENOTDIR, so assertion succeeds
      #    end
      def assert_raise_kind_of(*exp, &b)
        case exp.last
        when String, Proc
          msg = exp.pop
        end

        begin
          yield
        rescue Test::Unit::PendedError => e
          raise e unless exp.include? Test::Unit::PendedError
        rescue *exp => e
          pass
        rescue Exception => e
          flunk(message(msg) {"#{mu_pp(exp)} family exception expected, not #{mu_pp(e)}"})
        ensure
          unless e
            exp = exp.first if exp.size == 1

            flunk(message(msg) {"#{mu_pp(exp)} family expected but nothing was raised"})
          end
        end
        e
      end

      TEST_DIR = File.join(__dir__, "test/unit") #:nodoc:

      # :call-seq:
      #   assert(test, [failure_message])
      #
      #Tests if +test+ is true.
      #
      #+msg+ may be a String or a Proc. If +msg+ is a String, it will be used
      #as the failure message. Otherwise, the result of calling +msg+ will be
      #used as the message if the assertion fails.
      #
      #If no +msg+ is given, a default message will be used.
      #
      #    assert(false, "This was expected to be true")
      def assert(test, *msgs)
        case msg = msgs.first
        when String, Proc
        when nil
          msgs.shift
        else
          bt = caller.reject { |s| s.start_with?(TEST_DIR) }
          raise ArgumentError, "assertion message must be String or Proc, but #{msg.class} was given.", bt
        end unless msgs.empty?
        super
      end

      # :call-seq:
      #   assert_respond_to( object, method, failure_message = nil )
      #
      #Tests if the given Object responds to +method+.
      #
      #An optional failure message may be provided as the final argument.
      #
      #    assert_respond_to("hello", :reverse)  #Succeeds
      #    assert_respond_to("hello", :does_not_exist)  #Fails
      def assert_respond_to(obj, (meth, *priv), msg = nil)
        unless priv.empty?
          msg = message(msg) {
            "Expected #{mu_pp(obj)} (#{obj.class}) to respond to ##{meth}#{" privately" if priv[0]}"
          }
          return assert obj.respond_to?(meth, *priv), msg
        end
        #get rid of overcounting
        if caller_locations(1, 1)[0].path.start_with?(TEST_DIR)
          return if obj.respond_to?(meth)
        end
        super(obj, meth, msg)
      end

      # :call-seq:
      #   assert_not_respond_to( object, method, failure_message = nil )
      #
      #Tests if the given Object does not respond to +method+.
      #
      #An optional failure message may be provided as the final argument.
      #
      #    assert_not_respond_to("hello", :reverse)  #Fails
      #    assert_not_respond_to("hello", :does_not_exist)  #Succeeds
      def assert_not_respond_to(obj, (meth, *priv), msg = nil)
        unless priv.empty?
          msg = message(msg) {
            "Expected #{mu_pp(obj)} (#{obj.class}) to not respond to ##{meth}#{" privately" if priv[0]}"
          }
          return assert !obj.respond_to?(meth, *priv), msg
        end
        #get rid of overcounting
        if caller_locations(1, 1)[0].path.start_with?(TEST_DIR)
          return unless obj.respond_to?(meth)
        end
        refute_respond_to(obj, meth, msg)
      end

      # pattern_list is an array which contains regexp, string and :*.
      # :* means any sequence.
      #
      # pattern_list is anchored.
      # Use [:*, regexp/string, :*] for non-anchored match.
      def assert_pattern_list(pattern_list, actual, message=nil)
        rest = actual
        anchored = true
        pattern_list.each_with_index {|pattern, i|
          if pattern == :*
            anchored = false
          else
            if anchored
              match = rest.rindex(pattern, 0)
            else
              match = rest.index(pattern)
            end
            if match
              post_match = $~ ? $~.post_match : rest[match+pattern.size..-1]
            else
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
            rest = post_match
            anchored = true
          end
        }
        if anchored
          assert_equal("", rest)
        end
      end

      def assert_warning(pat, msg = nil)
        result = nil
        stderr = EnvUtil.with_default_internal(of: pat) {
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

      def assert_deprecated_warning(mesg = /deprecated/, &block)
        assert_warning(mesg) do
          EnvUtil.deprecation_warning(&block)
        end
      end

      def assert_deprecated_warn(mesg = /deprecated/, &block)
        assert_warn(mesg) do
          EnvUtil.deprecation_warning(&block)
        end
      end

      class << (AssertFile = Struct.new(:failure_message).new)
        include Assertions
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
          yield key
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
              (err.respond_to?(:full_message) ? err.full_message(highlight: false, order: :top) : err.message)
          }.join("\n---\n")
          if message
            msg = "#{message}\n#{msg}"
          end
          raise Test::Unit::AssertionFailedError, msg
        end
      end

      def assert_all?(obj, m = nil, &blk)
        failed = []
        obj.each do |*a, &b|
          unless blk.call(*a, &b)
            failed << (a.size > 1 ? a : a[0])
          end
        end
        assert(failed.empty?, message(m) {failed.pretty_inspect})
      end

      def assert_all_assertions(msg = nil)
        all = AllFailures.new
        yield all
      ensure
        assert(all.pass?, message(msg) {all.message.chomp(".")})
      end
      alias all_assertions assert_all_assertions

      def assert_all_assertions_foreach(msg = nil, *keys, &block)
        all = AllFailures.new
        all.foreach(*keys, &block)
      ensure
        assert(all.pass?, message(msg) {all.message.chomp(".")})
      end
      alias all_assertions_foreach assert_all_assertions_foreach

      %w[
        CLOCK_THREAD_CPUTIME_ID CLOCK_PROCESS_CPUTIME_ID
        CLOCK_MONOTONIC
      ].find do |c|
        if Process.const_defined?(c)
          [c.to_sym, Process.const_get(c)].find do |clk|
            begin
              Process.clock_gettime(clk)
            rescue
              # Constants may be defined but not implemented, e.g., mingw.
            else
              PERFORMANCE_CLOCK = clk
            end
          end
        end
      end

      # Expect +seq+ to respond to +first+ and +each+ methods, e.g.,
      # Array, Range, Enumerator::ArithmeticSequence and other
      # Enumerable-s, and each elements should be size factors.
      #
      # :yield: each elements of +seq+.
      def assert_linear_performance(seq, rehearsal: nil, pre: ->(n) {n})
        pend "No PERFORMANCE_CLOCK found" unless defined?(PERFORMANCE_CLOCK)

        # Timeout testing generally doesn't work when RJIT compilation happens.
        rjit_enabled = defined?(RubyVM::RJIT) && RubyVM::RJIT.enabled?
        measure = proc do |arg, message|
          st = Process.clock_gettime(PERFORMANCE_CLOCK)
          yield(*arg)
          t = (Process.clock_gettime(PERFORMANCE_CLOCK) - st)
          assert_operator 0, :<=, t, message unless rjit_enabled
          t
        end

        first = seq.first
        *arg = pre.call(first)
        times = (0..(rehearsal || (2 * first))).map do
          measure[arg, "rehearsal"].nonzero?
        end
        times.compact!
        tmin, tmax = times.minmax

        # safe_factor * tmax * rehearsal_time_variance_factor(equals to 1 when variance is small)
        tbase = 10 * tmax * [(tmax / tmin) ** 2 / 4, 1].max
        info = "(tmin: #{tmin}, tmax: #{tmax}, tbase: #{tbase})"

        seq.each do |i|
          next if i == first
          t = tbase * i.fdiv(first)
          *arg = pre.call(i)
          message = "[#{i}]: in #{t}s #{info}"
          Timeout.timeout(t, Timeout::Error, message) do
            measure[arg, message]
          end
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

      def new_test_token
        token = "\e[7;1m#{$$.to_s}:#{Time.now.strftime('%s.%L')}:#{rand(0x10000).to_s(16)}:\e[m"
        return token.dump, Regexp.quote(token)
      end

      # Platform predicates

      def self.mswin?
        defined?(@mswin) ? @mswin : @mswin = RUBY_PLATFORM.include?('mswin')
      end
      private def mswin?
        CoreAssertions.mswin?
      end

      def self.mingw?
        defined?(@mingw) ? @mingw : @mingw = RUBY_PLATFORM.include?('mingw')
      end
      private def mingw?
        CoreAssertions.mingw?
      end

      module_function def windows?
        mswin? or mingw?
      end

      def self.version_compare(expected, actual)
        expected.zip(actual).each {|e, a| z = (e <=> a); return z if z.nonzero?}
        0
      end

      def self.version_match?(expected, actual)
        if !actual
          false
        elsif expected.empty?
          true
        elsif expected.size == 1 and Range === (range = expected.first)
          b, e = range.begin, range.end
          return false if b and (c = version_compare(Array(b), actual)) > 0
          return false if e and (c = version_compare(Array(e), actual)) < 0
          return false if e and range.exclude_end? and c == 0
          true
        else
          version_compare(expected, actual).zero?
        end
      end

      def self.linux?(*ver)
        unless defined?(@linux)
          @linux = RUBY_PLATFORM.include?('linux') && `uname -r`.scan(/\d+/).map(&:to_i)
        end
        version_match? ver, @linux
      end
      private def linux?(*ver)
        CoreAssertions.linux?(*ver)
      end

      def self.glibc?(*ver)
        unless defined?(@glibc)
          libc = `/usr/bin/ldd /bin/sh`[/^\s*libc.*=> *\K\S*/]
          if libc and /version (\d+)\.(\d+)\.$/ =~ IO.popen([libc], &:read)[]
            @glibc = [$1.to_i, $2.to_i]
          else
            @glibc = false
          end
        end
        version_match? ver, @glibc
      end
      private def glibc?(*ver)
        CoreAssertions.glibc?(*ver)
      end

      def self.macos?(*ver)
        unless defined?(@macos)
          @macos = RUBY_PLATFORM.include?('darwin') && `sw_vers -productVersion`.scan(/\d+/).map(&:to_i)
        end
        version_match? ver, @macos
      end
      private def macos?(*ver)
        CoreAssertions.macos?(*ver)
      end
    end
  end
end
