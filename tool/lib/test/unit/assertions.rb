# frozen_string_literal: true
require 'pp'

module Test
  module Unit
    module Assertions

      ##
      # Returns the diff command to use in #diff. Tries to intelligently
      # figure out what diff to use.

      def self.diff
        unless defined? @diff
          exe = RbConfig::CONFIG['EXEEXT']
          @diff = %W"gdiff#{exe} diff#{exe}".find do |diff|
            if system(diff, "-u", __FILE__, __FILE__)
              break "#{diff} -u"
            end
          end
        end

        @diff
      end

      ##
      # Set the diff command to use in #diff.

      def self.diff= o
        @diff = o
      end

      ##
      # Returns a diff between +exp+ and +act+. If there is no known
      # diff command or if it doesn't make sense to diff the output
      # (single line, short output), then it simply returns a basic
      # comparison between the two.

      def diff exp, act
        require "tempfile"

        expect = mu_pp_for_diff exp
        butwas = mu_pp_for_diff act
        result = nil

        need_to_diff =
          self.class.diff &&
          (expect.include?("\n")    ||
          butwas.include?("\n")    ||
          expect.size > 30         ||
          butwas.size > 30         ||
          expect == butwas)

        return "Expected: #{mu_pp exp}\n  Actual: #{mu_pp act}" unless
          need_to_diff

        tempfile_a = nil
        tempfile_b = nil

        Tempfile.open("expect") do |a|
          tempfile_a = a
          a.puts expect
          a.flush

          Tempfile.open("butwas") do |b|
            tempfile_b = b
            b.puts butwas
            b.flush

            result = `#{self.class.diff} #{a.path} #{b.path}`
            result.sub!(/^\-\-\- .+/, "--- expected")
            result.sub!(/^\+\+\+ .+/, "+++ actual")

            if result.empty? then
              klass = exp.class
              result = [
                        "No visible difference in the #{klass}#inspect output.\n",
                        "You should look at the implementation of #== on ",
                        "#{klass} or its members.\n",
                        expect,
                      ].join
            end
          end
        end

        result
      ensure
        tempfile_a.close! if tempfile_a
        tempfile_b.close! if tempfile_b
      end

      ##
      # This returns a diff-able human-readable version of +obj+. This
      # differs from the regular mu_pp because it expands escaped
      # newlines and makes hex-values generic (like object_ids). This
      # uses mu_pp to do the first pass and then cleans it up.

      def mu_pp_for_diff obj
        mu_pp(obj).gsub(/(?<!\\)(?:\\\\)*\K\\n/, "\n").gsub(/:0x[a-fA-F0-9]{4,}/m, ':0xXXXXXX')
      end

      ##
      # Fails unless +test+ is a true value.

      def assert test, msg = nil
        msg ||= "Failed assertion, no message given."
        self._assertions += 1
        unless test then
          msg = msg.call if Proc === msg
          raise Test::Unit::AssertionFailedError, msg
        end
        true
      end

      ##
      # Fails unless +obj+ is empty.

      def assert_empty obj, msg = nil
        msg = message(msg) { "Expected #{mu_pp(obj)} to be empty" }
        assert_respond_to obj, :empty?
        assert obj.empty?, msg
      end

      ##
      # For comparing Floats.  Fails unless +exp+ and +act+ are within +delta+
      # of each other.
      #
      #   assert_in_delta Math::PI, (22.0 / 7.0), 0.01

      def assert_in_delta exp, act, delta = 0.001, msg = nil
        n = (exp - act).abs
        msg = message(msg) {
          "Expected |#{exp} - #{act}| (#{n}) to be <= #{delta}"
        }
        assert delta >= n, msg
      end

      ##
      # For comparing Floats.  Fails unless +exp+ and +act+ have a relative
      # error less than +epsilon+.

      def assert_in_epsilon a, b, epsilon = 0.001, msg = nil
        assert_in_delta a, b, [a.abs, b.abs].min * epsilon, msg
      end

      ##
      # Fails unless +collection+ includes +obj+.

      def assert_includes collection, obj, msg = nil
        msg = message(msg) {
          "Expected #{mu_pp(collection)} to include #{mu_pp(obj)}"
        }
        assert_respond_to collection, :include?
        assert collection.include?(obj), msg
      end

      ##
      # Fails unless +obj+ is an instance of +cls+.

      def assert_instance_of cls, obj, msg = nil
        msg = message(msg) {
          "Expected #{mu_pp(obj)} to be an instance of #{cls}, not #{obj.class}"
        }

        assert obj.instance_of?(cls), msg
      end

      ##
      # Fails unless +obj+ is a kind of +cls+.

      def assert_kind_of cls, obj, msg = nil # TODO: merge with instance_of
        msg = message(msg) {
          "Expected #{mu_pp(obj)} to be a kind of #{cls}, not #{obj.class}" }

        assert obj.kind_of?(cls), msg
      end

      ##
      # Fails unless +matcher+ <tt>=~</tt> +obj+.

      def assert_match matcher, obj, msg = nil
        msg = message(msg) { "Expected #{mu_pp matcher} to match #{mu_pp obj}" }
        assert_respond_to matcher, :"=~"
        matcher = Regexp.new Regexp.escape matcher if String === matcher
        assert matcher =~ obj, msg
      end

      ##
      # Fails unless +obj+ is nil

      def assert_nil obj, msg = nil
        msg = message(msg) { "Expected #{mu_pp(obj)} to be nil" }
        assert obj.nil?, msg
      end

      ##
      # For testing with binary operators.
      #
      #   assert_operator 5, :<=, 4

      def assert_operator o1, op, o2 = (predicate = true; nil), msg = nil
        return assert_predicate o1, op, msg if predicate
        msg = message(msg) { "Expected #{mu_pp(o1)} to be #{op} #{mu_pp(o2)}" }
        assert o1.__send__(op, o2), msg
      end

      ##
      # Fails if stdout or stderr do not output the expected results.
      # Pass in nil if you don't care about that streams output. Pass in
      # "" if you require it to be silent. Pass in a regexp if you want
      # to pattern match.
      #
      # NOTE: this uses #capture_io, not #capture_subprocess_io.
      #
      # See also: #assert_silent

      def assert_output stdout = nil, stderr = nil
        out, err = capture_output do
          yield
        end

        err_msg = Regexp === stderr ? :assert_match : :assert_equal if stderr
        out_msg = Regexp === stdout ? :assert_match : :assert_equal if stdout

        y = send err_msg, stderr, err, "In stderr" if err_msg
        x = send out_msg, stdout, out, "In stdout" if out_msg

        (!stdout || x) && (!stderr || y)
      end

      ##
      # For testing with predicates.
      #
      #   assert_predicate str, :empty?
      #
      # This is really meant for specs and is front-ended by assert_operator:
      #
      #   str.must_be :empty?

      def assert_predicate o1, op, msg = nil
        msg = message(msg) { "Expected #{mu_pp(o1)} to be #{op}" }
        assert o1.__send__(op), msg
      end

      ##
      # Fails unless +obj+ responds to +meth+.

      def assert_respond_to obj, meth, msg = nil
        msg = message(msg) {
          "Expected #{mu_pp(obj)} (#{obj.class}) to respond to ##{meth}"
        }
        assert obj.respond_to?(meth), msg
      end

      ##
      # Fails unless +exp+ and +act+ are #equal?

      def assert_same exp, act, msg = nil
        msg = message(msg) {
          data = [mu_pp(act), act.object_id, mu_pp(exp), exp.object_id]
          "Expected %s (oid=%d) to be the same as %s (oid=%d)" % data
        }
        assert exp.equal?(act), msg
      end

      ##
      # Fails if the block outputs anything to stderr or stdout.
      #
      # See also: #assert_output

      def assert_silent
        assert_output "", "" do
          yield
        end
      end

      ##
      # Fails unless the block throws +sym+

      def assert_throws sym, msg = nil
        default = "Expected #{mu_pp(sym)} to have been thrown"
        caught = true
        catch(sym) do
          begin
            yield
          rescue ThreadError => e       # wtf?!? 1.8 + threads == suck
            default += ", not \:#{e.message[/uncaught throw \`(\w+?)\'/, 1]}"
          rescue ArgumentError => e     # 1.9 exception
            default += ", not #{e.message.split(/ /).last}"
          rescue NameError => e         # 1.8 exception
            default += ", not #{e.name.inspect}"
          end
          caught = false
        end

        assert caught, message(msg) { default }
      end

      def assert_path_exists(path, msg = nil)
        msg = message(msg) { "Expected path '#{path}' to exist" }
        assert File.exist?(path), msg
      end
      alias assert_path_exist assert_path_exists
      alias refute_path_not_exist assert_path_exists

      def refute_path_exists(path, msg = nil)
        msg = message(msg) { "Expected path '#{path}' to not exist" }
        refute File.exist?(path), msg
      end
      alias refute_path_exist refute_path_exists
      alias assert_path_not_exist refute_path_exists

      ##
      # Captures $stdout and $stderr into strings:
      #
      #   out, err = capture_output do
      #     puts "Some info"
      #     warn "You did a bad thing"
      #   end
      #
      #   assert_match %r%info%, out
      #   assert_match %r%bad%, err

      def capture_output
        require 'stringio'

        captured_stdout, captured_stderr = StringIO.new, StringIO.new

        synchronize do
          orig_stdout, orig_stderr = $stdout, $stderr
          $stdout, $stderr         = captured_stdout, captured_stderr

          begin
            yield
          ensure
            $stdout = orig_stdout
            $stderr = orig_stderr
          end
        end

        return captured_stdout.string, captured_stderr.string
      end

      def capture_io
        raise NoMethodError, "use capture_output"
      end

      ##
      # Fails with +msg+

      def flunk msg = nil
        msg ||= "Epic Fail!"
        assert false, msg
      end

      ##
      # used for counting assertions

      def pass msg = nil
        assert true
      end

      ##
      # Fails if +test+ is a true value

      def refute test, msg = nil
        msg ||= "Failed refutation, no message given"
        not assert(! test, msg)
      end

      ##
      # Fails if +obj+ is empty.

      def refute_empty obj, msg = nil
        msg = message(msg) { "Expected #{mu_pp(obj)} to not be empty" }
        assert_respond_to obj, :empty?
        refute obj.empty?, msg
      end

      ##
      # Fails if <tt>exp == act</tt>.
      #
      # For floats use refute_in_delta.

      def refute_equal exp, act, msg = nil
        msg = message(msg) {
          "Expected #{mu_pp(act)} to not be equal to #{mu_pp(exp)}"
        }
        refute exp == act, msg
      end

      ##
      # For comparing Floats.  Fails if +exp+ is within +delta+ of +act+.
      #
      #   refute_in_delta Math::PI, (22.0 / 7.0)

      def refute_in_delta exp, act, delta = 0.001, msg = nil
        n = (exp - act).abs
        msg = message(msg) {
          "Expected |#{exp} - #{act}| (#{n}) to not be <= #{delta}"
        }
        refute delta >= n, msg
      end

      ##
      # For comparing Floats.  Fails if +exp+ and +act+ have a relative error
      # less than +epsilon+.

      def refute_in_epsilon a, b, epsilon = 0.001, msg = nil
        refute_in_delta a, b, a * epsilon, msg
      end

      ##
      # Fails if +collection+ includes +obj+.

      def refute_includes collection, obj, msg = nil
        msg = message(msg) {
          "Expected #{mu_pp(collection)} to not include #{mu_pp(obj)}"
        }
        assert_respond_to collection, :include?
        refute collection.include?(obj), msg
      end

      ##
      # Fails if +obj+ is an instance of +cls+.

      def refute_instance_of cls, obj, msg = nil
        msg = message(msg) {
          "Expected #{mu_pp(obj)} to not be an instance of #{cls}"
        }
        refute obj.instance_of?(cls), msg
      end

      ##
      # Fails if +obj+ is a kind of +cls+.

      def refute_kind_of cls, obj, msg = nil # TODO: merge with instance_of
        msg = message(msg) { "Expected #{mu_pp(obj)} to not be a kind of #{cls}" }
        refute obj.kind_of?(cls), msg
      end

      ##
      # Fails if +matcher+ <tt>=~</tt> +obj+.

      def refute_match matcher, obj, msg = nil
        msg = message(msg) {"Expected #{mu_pp matcher} to not match #{mu_pp obj}"}
        assert_respond_to matcher, :"=~"
        matcher = Regexp.new Regexp.escape matcher if String === matcher
        refute matcher =~ obj, msg
      end

      ##
      # Fails if +obj+ is nil.

      def refute_nil obj, msg = nil
        msg = message(msg) { "Expected #{mu_pp(obj)} to not be nil" }
        refute obj.nil?, msg
      end

      ##
      # Fails if +o1+ is not +op+ +o2+. Eg:
      #
      #   refute_operator 1, :>, 2 #=> pass
      #   refute_operator 1, :<, 2 #=> fail

      def refute_operator o1, op, o2 = (predicate = true; nil), msg = nil
        return refute_predicate o1, op, msg if predicate
        msg = message(msg) { "Expected #{mu_pp(o1)} to not be #{op} #{mu_pp(o2)}"}
        refute o1.__send__(op, o2), msg
      end

      ##
      # For testing with predicates.
      #
      #   refute_predicate str, :empty?
      #
      # This is really meant for specs and is front-ended by refute_operator:
      #
      #   str.wont_be :empty?

      def refute_predicate o1, op, msg = nil
        msg = message(msg) { "Expected #{mu_pp(o1)} to not be #{op}" }
        refute o1.__send__(op), msg
      end

      ##
      # Fails if +obj+ responds to the message +meth+.

      def refute_respond_to obj, meth, msg = nil
        msg = message(msg) { "Expected #{mu_pp(obj)} to not respond to #{meth}" }

        refute obj.respond_to?(meth), msg
      end

      ##
      # Fails if +exp+ is the same (by object identity) as +act+.

      def refute_same exp, act, msg = nil
        msg = message(msg) {
          data = [mu_pp(act), act.object_id, mu_pp(exp), exp.object_id]
          "Expected %s (oid=%d) to not be the same as %s (oid=%d)" % data
        }
        refute exp.equal?(act), msg
      end

      ##
      # Skips the current test. Gets listed at the end of the run but
      # doesn't cause a failure exit code.

      def pend msg = nil, bt = caller
        msg ||= "Skipped, no message given"
        @skip = true
        raise Test::Unit::PendedError, msg, bt
      end
      alias omit pend

      # TODO: Removed this and enabled to raise NoMethodError with skip
      alias skip pend
      # def skip(msg = nil, bt = caller)
      #   raise NoMethodError, "use omit or pend", caller
      # end

      ##
      # Was this testcase skipped? Meant for #teardown.

      def skipped?
        defined?(@skip) and @skip
      end

      ##
      # Takes a block and wraps it with the runner's shared mutex.

      def synchronize
        Test::Unit::Runner.runner.synchronize do
          yield
        end
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

      def assert_not_all?(obj, m = nil, &blk)
        failed = []
        obj.each do |*a, &b|
          if blk.call(*a, &b)
            failed << (a.size > 1 ? a : a[0])
          end
        end
        assert(failed.empty?, message(m) {failed.pretty_inspect})
      end

      def assert_syntax_error(code, error, *args, **opt)
        prepare_syntax_check(code, *args, **opt) do |src, fname, line, mesg|
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
      MIN_HZ = /mswin|mingw/ =~ RUBY_PLATFORM ? 67 : 100
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

      def build_message(head, template=nil, *arguments) #:nodoc:
        template &&= template.chomp
        template.gsub(/\G((?:[^\\]|\\.)*?)(\\)?\?/) { $1 + ($2 ? "?" : mu_pp(arguments.shift)) }
      end
    end
  end
end
