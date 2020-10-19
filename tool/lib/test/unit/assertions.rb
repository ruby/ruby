# frozen_string_literal: true
require 'minitest/unit'
require 'test/unit/core_assertions'
require 'pp'

module Test
  module Unit
    module Assertions
      include Test::Unit::CoreAssertions

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
