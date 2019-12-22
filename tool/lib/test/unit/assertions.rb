# frozen_string_literal: true
require 'minitest/unit'
require 'test/unit/core_assertions'
require 'pp'

module Test
  module Unit
    module Assertions
      include Test::Unit::CoreAssertions

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

      def assert_raises(*exp, &b)
        raise NoMethodError, "use assert_raise", caller
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
        mname = ('assert_not_'.dup << m.to_s[/.*?_(.*)/, 1])
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
            failed << (a.size > 1 ? a : a[0])
          end
        end
        assert(failed.empty?, message(m) {failed.pretty_inspect})
      end

      # compatibility with test-unit
      alias pend skip

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

      def assert_syntax_error(code, error, *args)
        prepare_syntax_check(code, *args) do |src, fname, line, mesg|
          yield if defined?(yield)
          e = assert_raise(SyntaxError, mesg) do
            syntax_check(src, fname, line)
          end
          assert_match(error, e.message, mesg)
          e
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

      def assert_no_warning(pat, msg = nil)
        result = nil
        stderr = EnvUtil.verbose_warning {
          EnvUtil.with_default_internal(pat.encoding) {
            result = yield
          }
        }
        msg = message(msg) {diff pat, stderr}
        refute(pat === stderr, msg)
        result
      end

      def assert_no_memory_leak(args, prepare, code, message=nil, limit: 2.0, rss: false, **opt)
        # TODO: consider choosing some appropriate limit for MJIT and stop skipping this once it does not randomly fail
        skip 'assert_no_memory_leak may consider MJIT memory usage as leak' if defined?(RubyVM::MJIT) && RubyVM::MJIT.enabled?

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

      # kernel resolution can limit the minimum time we can measure
      # [ruby-core:81540]
      MIN_HZ = MiniTest::Unit::TestCase.windows? ? 67 : 100
      MIN_MEASURABLE = 1.0 / MIN_HZ

      def assert_cpu_usage_low(msg = nil, pct: 0.05, wait: 1.0, stop: nil)
        require 'benchmark'

        wait = EnvUtil.apply_timeout_scale(wait)
        if wait < 0.1 # TIME_QUANTUM_USEC in thread_pthread.c
          warn "test #{msg || 'assert_cpu_usage_low'} too short to be accurate"
        end
        tms = Benchmark.measure(msg || '') do
          if stop
            th = Thread.start {sleep wait; stop.call}
            yield
            th.join
          else
            begin
              Timeout.timeout(wait) {yield}
            rescue Timeout::Error
            end
          end
        end

        max = pct * tms.real
        min_measurable = MIN_MEASURABLE
        min_measurable *= 1.30 # add a little (30%) to account for misc. overheads
        if max < min_measurable
          max = min_measurable
        end

        assert_operator tms.total, :<=, max, msg
      end

      def assert_is_minus_zero(f)
        assert(1.0/f == -Float::INFINITY, "#{f} is not -0.0")
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

      def assert_all_assertions_foreach(msg = nil, *keys, &block)
        all = AllFailures.new
        all.foreach(*keys, &block)
      ensure
        assert(all.pass?, message(msg) {all.message.chomp(".")})
      end
      alias all_assertions_foreach assert_all_assertions_foreach

      def build_message(head, template=nil, *arguments) #:nodoc:
        template &&= template.chomp
        template.gsub(/\G((?:[^\\]|\\.)*?)(\\)?\?/) { $1 + ($2 ? "?" : mu_pp(arguments.shift)) }
      end
    end
  end
end
