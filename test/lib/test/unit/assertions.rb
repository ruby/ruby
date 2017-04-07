# frozen_string_literal: false
require 'minitest/unit'
require 'pp'

module Test
  module Unit
    module Assertions
      include MiniTest::Assertions

      def mu_pp(obj) #:nodoc:
        obj.pretty_inspect.chomp
      end

      MINI_DIR = File.join(File.dirname(File.dirname(File.expand_path(__FILE__))), "minitest") #:nodoc:

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
          bt = caller.reject { |s| s.start_with?(MINI_DIR) }
          raise ArgumentError, "assertion message must be String or Proc, but #{msg.class} was given.", bt
        end unless msgs.empty?
        super
      end

      # :call-seq:
      #   assert_block( failure_message = nil )
      #
      #Tests the result of the given block. If the block does not return true,
      #the assertion will fail. The optional +failure_message+ argument is the same as in
      #Assertions#assert.
      #
      #    assert_block do
      #      [1, 2, 3].any? { |num| num < 1 }
      #    end
      def assert_block(*msgs)
        assert yield, *msgs
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
            exception_details(e, message(msg) {"#{mu_pp(exp)} exception expected, not"}.call)
          }

          return e
        end

        exp = exp.first if exp.size == 1

        flunk(message(msg) {"#{mu_pp(exp)} expected but nothing was raised"})
      end

      def assert_raises(*exp, &b)
        raise NoMethodError, "use assert_raise", caller
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
            msg = message(msg) { "Exception raised:\n<#{mu_pp(e)}>" }
            raise MiniTest::Assertion, msg.call, bt
          else
            raise
          end
        end
      end

      # :call-seq:
      #   assert_nothing_thrown( failure_message = nil, &block )
      #
      #Fails if the given block uses a call to Kernel#throw, and
      #returns the result of the block otherwise.
      #
      #An optional failure message may be provided as the final argument.
      #
      #    assert_nothing_thrown "Something was thrown!" do
      #      throw :problem?
      #    end
      def assert_nothing_thrown(msg=nil)
        begin
          ret = yield
        rescue ArgumentError => error
          raise error if /\Auncaught throw (.+)\z/m !~ error.message
          msg = message(msg) { "<#{$1}> was thrown when nothing was expected" }
          flunk(msg)
        end
        assert(true, "Expected nothing to be thrown")
        ret
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
      #   assert_equal( expected, actual, failure_message = nil )
      #
      #Tests if +expected+ is equal to +actual+.
      #
      #An optional failure message may be provided as the final argument.
      def assert_equal(exp, act, msg = nil)
        msg = message(msg) {
          exp_str = mu_pp(exp)
          act_str = mu_pp(act)
          exp_comment = ''
          act_comment = ''
          if exp_str == act_str
            if (exp.is_a?(String) && act.is_a?(String)) ||
               (exp.is_a?(Regexp) && act.is_a?(Regexp))
              exp_comment = " (#{exp.encoding})"
              act_comment = " (#{act.encoding})"
            elsif exp.is_a?(Float) && act.is_a?(Float)
              exp_str = "%\#.#{Float::DIG+2}g" % exp
              act_str = "%\#.#{Float::DIG+2}g" % act
            elsif exp.is_a?(Time) && act.is_a?(Time)
              if exp.subsec * 1000_000_000 == exp.nsec
                exp_comment = " (#{exp.nsec}[ns])"
              else
                exp_comment = " (subsec=#{exp.subsec})"
              end
              if act.subsec * 1000_000_000 == act.nsec
                act_comment = " (#{act.nsec}[ns])"
              else
                act_comment = " (subsec=#{act.subsec})"
              end
            elsif exp.class != act.class
              # a subclass of Range, for example.
              exp_comment = " (#{exp.class})"
              act_comment = " (#{act.class})"
            end
          elsif !Encoding.compatible?(exp_str, act_str)
            if exp.is_a?(String) && act.is_a?(String)
              exp_str = exp.dump
              act_str = act.dump
              exp_comment = " (#{exp.encoding})"
              act_comment = " (#{act.encoding})"
            else
              exp_str = exp_str.dump
              act_str = act_str.dump
            end
          end
          "<#{exp_str}>#{exp_comment} expected but was\n<#{act_str}>#{act_comment}"
        }
        assert(exp == act, msg)
      end

      # :call-seq:
      #   assert_not_nil( expression, failure_message = nil )
      #
      #Tests if +expression+ is not nil.
      #
      #An optional failure message may be provided as the final argument.
      def assert_not_nil(exp, msg=nil)
        msg = message(msg) { "<#{mu_pp(exp)}> expected to not be nil" }
        assert(!exp.nil?, msg)
      end

      # :call-seq:
      #   assert_not_equal( expected, actual, failure_message = nil )
      #
      #Tests if +expected+ is not equal to +actual+.
      #
      #An optional failure message may be provided as the final argument.
      def assert_not_equal(exp, act, msg=nil)
        msg = message(msg) { "<#{mu_pp(exp)}> expected to be != to\n<#{mu_pp(act)}>" }
        assert(exp != act, msg)
      end

      # :call-seq:
      #   assert_no_match( regexp, string, failure_message = nil )
      #
      #Tests if the given Regexp does not match a given String.
      #
      #An optional failure message may be provided as the final argument.
      def assert_no_match(regexp, string, msg=nil)
        assert_instance_of(Regexp, regexp, "The first argument to assert_no_match should be a Regexp.")
        self._assertions -= 1
        msg = message(msg) { "<#{mu_pp(regexp)}> expected to not match\n<#{mu_pp(string)}>" }
        assert(regexp !~ string, msg)
      end

      # :call-seq:
      #   assert_not_same( expected, actual, failure_message = nil )
      #
      #Tests if +expected+ is not the same object as +actual+.
      #This test uses Object#equal? to test equality.
      #
      #An optional failure message may be provided as the final argument.
      #
      #    assert_not_same("x", "x") #Succeeds
      def assert_not_same(expected, actual, message="")
        msg = message(msg) { build_message(message, <<EOT, expected, expected.__id__, actual, actual.__id__) }
<?>
with id <?> expected to not be equal\\? to
<?>
with id <?>.
EOT
        assert(!actual.equal?(expected), msg)
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
        if caller_locations(1, 1)[0].path.start_with?(MINI_DIR)
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
        if caller_locations(1, 1)[0].path.start_with?(MINI_DIR)
          return unless obj.respond_to?(meth)
        end
        refute_respond_to(obj, meth, msg)
      end

      # :call-seq:
      #   assert_send( +send_array+, failure_message = nil )
      #
      # Passes if the method send returns a true value.
      #
      # +send_array+ is composed of:
      # * A receiver
      # * A method
      # * Arguments to the method
      #
      # Example:
      #   assert_send(["Hello world", :include?, "Hello"])    # -> pass
      #   assert_send(["Hello world", :include?, "Goodbye"])  # -> fail
      def assert_send send_ary, m = nil
        recv, msg, *args = send_ary
        m = message(m) {
          if args.empty?
            argsstr = ""
          else
            (argsstr = mu_pp(args)).sub!(/\A\[(.*)\]\z/m, '(\1)')
          end
          "Expected #{mu_pp(recv)}.#{msg}#{argsstr} to return true"
        }
        assert recv.__send__(msg, *args), m
      end

      # :call-seq:
      #   assert_not_send( +send_array+, failure_message = nil )
      #
      # Passes if the method send doesn't return a true value.
      #
      # +send_array+ is composed of:
      # * A receiver
      # * A method
      # * Arguments to the method
      #
      # Example:
      #   assert_not_send([[1, 2], :member?, 1]) # -> fail
      #   assert_not_send([[1, 2], :member?, 4]) # -> pass
      def assert_not_send send_ary, m = nil
        recv, msg, *args = send_ary
        m = message(m) {
          if args.empty?
            argsstr = ""
          else
            (argsstr = mu_pp(args)).sub!(/\A\[(.*)\]\z/m, '(\1)')
          end
          "Expected #{mu_pp(recv)}.#{msg}#{argsstr} to return false"
        }
        assert !recv.__send__(msg, *args), m
      end

      ms = instance_methods(true).map {|sym| sym.to_s }
      ms.grep(/\Arefute_/) do |m|
        mname = ('assert_not_' << m.to_s[/.*?_(.*)/, 1])
        alias_method(mname, m) unless ms.include? mname
      end
      alias assert_include assert_includes
      alias assert_not_include assert_not_includes

      def assert_all?(obj, m = nil, &blk)
        failed = []
        obj.each do |*a, &b|
          unless blk.call(*a, &b)
            failed << (a.size > 1 ? a : a[0])
          end
        end
        assert(failed.empty?, message(m) {failed.pretty_inspect})
      end

      def assert_not_all?(obj, m = nil, &blk)
        failed = []
        obj.each do |*a, &b|
          if blk.call(*a, &b)
            failed << a.size > 1 ? a : a[0]
          end
        end
        assert(failed.empty?, message(m) {failed.pretty_inspect})
      end

      # compatibility with test-unit
      alias pend skip

      def prepare_syntax_check(code, fname = caller_locations(2, 1)[0], mesg = fname.to_s, verbose: nil)
        code = code.dup.force_encoding(Encoding::UTF_8)
        verbose, $VERBOSE = $VERBOSE, verbose
        case
        when Array === fname
          fname, line = *fname
        when defined?(fname.path) && defined?(fname.lineno)
          fname, line = fname.path, fname.lineno
        else
          line = 1
        end
        yield(code, fname, line, mesg)
      ensure
        $VERBOSE = verbose
      end

      def assert_valid_syntax(code, *args)
        prepare_syntax_check(code, *args) do |src, fname, line, mesg|
          yield if defined?(yield)
          assert_nothing_raised(SyntaxError, mesg) do
            RubyVM::InstructionSequence.compile(src, fname, fname, line)
          end
        end
      end

      def assert_syntax_error(code, error, *args)
        prepare_syntax_check(code, *args) do |src, fname, line, mesg|
          yield if defined?(yield)
          e = assert_raise(SyntaxError, mesg) do
            RubyVM::InstructionSequence.compile(src, fname, fname, line)
          end
          assert_match(error, e.message, mesg)
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
            sigdesc << " (core dumped)"
          end
          full_message = ''
          message = message.call if Proc === message
          if message and !message.empty?
            full_message << message << "\n"
          end
          full_message << "pid #{pid}"
          full_message << " exit #{status.exitstatus}" if status.exited?
          full_message << " killed by #{sigdesc}" if sigdesc
          if out and !out.empty?
            full_message << "\n#{out.b.gsub(/^/, '| ')}"
            full_message << "\n" if /\n\z/ !~ full_message
          end
          if log
            full_message << "\n#{log.b.gsub(/^/, '| ')}"
          end
          full_message
        end
        faildesc
      end

      def assert_in_out_err(args, test_stdin = "", test_stdout = [], test_stderr = [], message = nil,
                            success: nil, **opt)
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

      def assert_warning(pat, msg = nil)
        stderr = EnvUtil.verbose_warning {
          EnvUtil.with_default_internal(pat.encoding) {
            yield
          }
        }
        msg = message(msg) {diff pat, stderr}
        assert(pat === stderr, msg)
      end

      def assert_warn(*args)
        assert_warning(*args) {$VERBOSE = false; yield}
      end

      def assert_no_memory_leak(args, prepare, code, message=nil, limit: 2.0, rss: false, **opt)
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
        skip
      end

      def assert_is_minus_zero(f)
        assert(1.0/f == -Float::INFINITY, "#{f} is not -0.0")
      end

      def assert_file
        AssertFile
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
                  actual_mesg = "to match\n"
                  rest.scan(/.*\n+/) {
                    actual_mesg << '  ' << $&.inspect << "+\n"
                  }
                  actual_mesg.sub!(/\+\n\z/, '')
                else
                  actual_mesg = "to match #{mu_pp rest}"
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
          end
        end
        if !errs.empty?
          msg = "exceptions on #{errs.length} threads:\n" +
            errs.map {|t, err|
            "#{t.inspect}:\n" +
            err.backtrace.map.with_index {|line, i|
              if i == 0
                "#{line}: #{err.message} (#{err.class})"
              else
                "\tfrom #{line}"
              end
            }.join("\n")
          }.join("\n---\n")
          if message
            msg = "#{message}\n#{msg}"
          end
          raise MiniTest::Assertion, msg
        end
        values
      end

      class << (AssertFile = Struct.new(:failure_message).new)
        include Assertions
        def assert_file_predicate(predicate, *args)
          if /\Anot_/ =~ predicate
            predicate = $'
            neg = " not"
          end
          result = File.__send__(predicate, *args)
          result = !result if neg
          mesg = "Expected file " << args.shift.inspect
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

        def message
          i = 0
          total = @count.to_s
          fmt = "%#{total.size}d"
          @failures.map {|k, (n, v)|
            "\n#{i+=1}. [#{fmt%n}/#{total}] Assertion for #{k.inspect}\n#{v.message.b.gsub(/^/, '   | ')}"
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

      def build_message(head, template=nil, *arguments) #:nodoc:
        template &&= template.chomp
        template.gsub(/\G((?:[^\\]|\\.)*?)(\\)?\?/) { $1 + ($2 ? "?" : mu_pp(arguments.shift)) }
      end

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
    end
  end
end
